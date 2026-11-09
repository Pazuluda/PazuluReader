import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/source.dart';
import '../../core/source_health.dart' show isNonPublicIpAddress;
import '../availability.dart';
import '../cache/lru_cache.dart';
import '../diagnostics/engine_log.dart';
import '../routing/circuit_breaker.dart';

typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// Lightweight cancellation: requests check it between steps and the caller
/// drops late results (http 1.x cannot abort a socket mid-flight portably).
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => 'Requête annulée.';
}

class EngineResponse {
  const EngineResponse({
    required this.status,
    required this.bytes,
    required this.headers,
    required this.finalUri,
    this.truncated = false,
    this.fromCache = false,
    this.elapsed = Duration.zero,
  });

  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
  final Uri finalUri;
  final bool truncated;
  final bool fromCache;
  final Duration elapsed;

  String get text => utf8.decode(bytes, allowMalformed: true);
  String? get contentType => headers['content-type'];
  bool get ok => status >= 200 && status < 300;
}

/// Per-host pacing: limited concurrency and a minimum gap between requests.
class _HostGate {
  _HostGate(this.maxConcurrent, this.minInterval);

  int maxConcurrent;
  Duration minInterval;
  int _running = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() async {
    while (_running >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    final wait = _last.add(minInterval).difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
  }

  void release() {
    _running--;
    if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
  }
}

/// The only network path of the Source Engine 2.0.
///
/// * HTTPS only, no credentials in URLs, no explicit ports;
/// * host allow-list per extension, re-checked on every redirect (manual
///   redirect handling, max 5 hops);
/// * SSRF guard: DNS answers pointing to private / loopback / link-local
///   networks are refused;
/// * HTTP 429 honours Retry-After through the circuit breaker; no retry storm;
/// * transient network/5xx failures get one bounded retry;
/// * concurrent identical GETs are de-duplicated, small text responses are
///   kept in an LRU with TTL; image bytes are never cached here.
class EngineHttpClient {
  EngineHttpClient({
    http.Client? client,
    HostResolver? resolver,
    CircuitBreaker? breaker,
    EngineLog? log,
    this.userAgent = 'PazuluReader/2.0 (Windows; lecteur personnel)',
    this.checkDns = true,
  })  : _client = client ?? http.Client(),
        _resolver = resolver ?? InternetAddress.lookup,
        breaker = breaker ?? CircuitBreaker(),
        log = log ?? EngineLog();

  final http.Client _client;
  final HostResolver _resolver;
  final CircuitBreaker breaker;
  final EngineLog log;
  final String userAgent;

  /// Tests with an in-memory client can disable DNS resolution.
  final bool checkDns;

  final Map<String, _HostGate> _gates = {};
  final Map<String, Future<EngineResponse>> _inFlight = {};
  final LruCache<String, EngineResponse> _textCache = LruCache(
    maxEntries: 96,
    maxWeight: 12 * 1024 * 1024,
    weigh: (r) => r.bytes.length,
    ttl: const Duration(minutes: 5),
  );
  final Map<String, (DateTime, bool)> _dnsVerdicts = {};

  /// Applies an extension's declared rate limits to its hosts.
  void configureHost(String host, {int? maxConcurrent, int? requestsPerMinute}) {
    final gate = _gateFor(host);
    if (maxConcurrent != null && maxConcurrent > 0) {
      gate.maxConcurrent = maxConcurrent.clamp(1, 6).toInt();
    }
    if (requestsPerMinute != null && requestsPerMinute > 0) {
      final ms = (60000 / requestsPerMinute.clamp(1, 600)).round();
      gate.minInterval = Duration(milliseconds: ms);
    }
  }

  _HostGate _gateFor(String host) => _gates.putIfAbsent(host.toLowerCase(),
      () => _HostGate(2, const Duration(milliseconds: 250)));

  static bool hostAllowed(String host, Iterable<String> allowed) {
    final h = host.toLowerCase();
    for (final a in allowed) {
      final d = a.toLowerCase();
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  static Uri checkUrl(Uri uri, Iterable<String> allowedHosts) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw const SourceException('Adresse refusée : HTTPS standard requis.');
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') ||
        host.endsWith('.internal') || host.contains(':') ||
        RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(host)) {
      throw const SourceException('Adresse locale ou IP directe refusée.');
    }
    if (allowedHosts.isNotEmpty && !hostAllowed(host, allowedHosts)) {
      throw SourceException('Domaine non autorisé pour cette source : $host');
    }
    return uri;
  }

  Future<void> _checkDns(String host) async {
    if (!checkDns) return;
    final cached = _dnsVerdicts[host];
    if (cached != null && DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      if (!cached.$2) throw const SourceException('Le domaine pointe vers un réseau privé.');
      return;
    }
    List<InternetAddress> addresses;
    try {
      addresses = await _resolver(host).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const SourceException('Résolution DNS trop lente.');
    } catch (_) {
      throw SourceException('Domaine introuvable ($host).');
    }
    final ok = addresses.isNotEmpty && !addresses.any(isNonPublicIpAddress);
    _dnsVerdicts[host] = (DateTime.now(), ok);
    if (!ok) throw const SourceException('Le domaine pointe vers un réseau privé.');
  }

  /// GET with all engine protections.
  ///
  /// [allowedHosts]: empty means "the original host only".
  /// [truncateAt]: read only the first bytes (image probes) and stop.
  /// [maxBytes]: hard limit for full reads.
  Future<EngineResponse> get(
    Uri uri, {
    Iterable<String> allowedHosts = const [],
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 8 * 1024 * 1024,
    int? truncateAt,
    bool cache = false,
    int retries = 2,
    String? sourceId,
    CancelToken? cancel,
    String method = 'GET',
    bool anyPublicHost = false,
    String? body,
  }) {
    if (method != 'GET' && method != 'POST') {
      throw ArgumentError.value(method, 'method');
    }
    final hosts = allowedHosts.isEmpty ? <String>[uri.host] : allowedHosts.toList();
    checkUrl(uri, hosts);
    final key = '$method|${truncateAt ?? 'full'}|${_headerKey(headers)}|$uri|'
        '${body == null ? '' : body.hashCode}';
    if (cache) {
      final hit = _textCache.get(key);
      if (hit != null) {
        return Future.value(EngineResponse(status: hit.status, bytes: hit.bytes,
            headers: hit.headers, finalUri: hit.finalUri, fromCache: true));
      }
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    // Image CDNs often redirect to another CDN: with [anyPublicHost] the
    // allow-list is replaced by the HTTPS + public-DNS checks alone.
    final effectiveHosts = anyPublicHost ? const <String>[] : hosts;
    final future = _getWithRetries(method, uri, effectiveHosts, headers, timeout, maxBytes,
        truncateAt, retries, sourceId, cancel, body).then((response) {
      if (cache && response.ok && !response.truncated) _textCache.put(key, response);
      return response;
    });
    _inFlight[key] = future;
    future.whenComplete(() {
      _inFlight.remove(key);
    }).ignore();
    return future;
  }

  static String _headerKey(Map<String, String> headers) {
    final keys = headers.keys.toList()..sort();
    return keys.map((k) => '$k=${headers[k]}').join(';');
  }

  Future<EngineResponse> _getWithRetries(String method, Uri uri, List<String> hosts,
      Map<String, String> headers, Duration timeout, int maxBytes, int? truncateAt,
      int retries, String? sourceId, CancelToken? cancel, String? body) async {
    var attempt = 0;
    while (true) {
      try {
        return await _getOnce(method, uri, hosts, headers, timeout, maxBytes,
            truncateAt, sourceId, cancel, body);
      } on _TransientFailure catch (failure) {
        if (attempt >= retries || (cancel?.isCancelled ?? false)) {
          breaker.recordFailure(uri.host, reason: failure.message);
          throw SourceException(failure.message, statusCode: failure.status);
        }
        attempt++;
        // 502/503/504 are usually a busy origin behind a CDN: wait longer.
        final serverBusy = (failure.status ?? 0) >= 500;
        await Future<void>.delayed(Duration(milliseconds:
            (serverBusy ? 1200 : 450) * attempt * attempt));
      }
    }
  }

  Future<EngineResponse> _getOnce(String method, Uri start, List<String> hosts,
      Map<String, String> headers, Duration timeout, int maxBytes, int? truncateAt,
      String? sourceId, CancelToken? cancel, String? body) async {
    final watch = Stopwatch()..start();
    var current = start;
    for (var hop = 0; hop <= 5; hop++) {
      if (cancel?.isCancelled ?? false) throw const RequestCancelled();
      checkUrl(current, hosts);
      final host = current.host.toLowerCase();
      if (!breaker.allow(host)) {
        final wait = breaker.retryIn(host);
        throw ChapterRestrictedException(
            'Source momentanément mise en pause ($host)'
            '${wait == null ? '' : ', nouvel essai dans ${wait.inSeconds + 1} s'}.',
            kind: AccessKind.rateLimited, retryAfter: wait);
      }
      await _checkDns(host);
      final gate = _gateFor(host);
      await gate.acquire();
      http.StreamedResponse response;
      try {
        // A redirect after POST continues as GET (RFC 9110 practice).
        final request = http.Request(hop == 0 ? method : 'GET', current)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': userAgent,
            'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
            ...headers,
          });
        if (body != null && hop == 0) request.body = body;
        if (truncateAt != null && !request.headers.containsKey('Range')) {
          request.headers['Range'] = 'bytes=0-${truncateAt - 1}';
        }
        try {
          response = await _client.send(request).timeout(timeout);
        } on TimeoutException {
          throw _TransientFailure('Délai dépassé ($host).');
        } on RequestCancelled {
          rethrow;
        } catch (e) {
          throw _TransientFailure('Connexion impossible ($host) : ${_short(e)}');
        }

        final status = response.statusCode;
        if (status >= 300 && status < 400) {
          final location = response.headers['location'];
          await response.stream.drain<void>().catchError((_) {});
          if (location == null || location.isEmpty) {
            throw SourceException('Redirection sans destination ($host).', statusCode: status);
          }
          var next = current.resolve(location);
          // Many sites redirect to « http://www… » : asked again in HTTPS
          // (never followed in clear text).
          if (next.scheme == 'http' && (!next.hasPort || next.port == 80)) {
            next = next.replace(scheme: 'https', port: 443);
          }
          if (hosts.isNotEmpty && !hostAllowed(next.host, hosts)) {
            log.warn('redirect_refused', sourceId: sourceId,
                message: '$host → ${next.host}');
            throw SourceException('Redirection vers un autre domaine refusée '
                '(${next.host}). La source a peut-être changé de domaine.',
                statusCode: status);
          }
          current = next;
          continue;
        }
        if (status == 429) {
          await response.stream.drain<void>().catchError((_) {});
          final retryAfter = parseRetryAfter(response.headers['retry-after']) ??
              const Duration(seconds: 60);
          breaker.openFor(host, retryAfter, reason: 'HTTP 429');
          log.warn('rate_limited', sourceId: sourceId,
              message: '$host Retry-After ${retryAfter.inSeconds}s');
          throw ChapterRestrictedException(
              'La source limite les requêtes (HTTP 429). Nouvel essai possible '
              'dans ${retryAfter.inSeconds} s ; aucune relance forcée.',
              kind: AccessKind.rateLimited, statusCode: 429, retryAfter: retryAfter);
        }
        if (status >= 500 && status != 501) {
          await response.stream.drain<void>().catchError((_) {});
          throw _TransientFailure('Erreur serveur HTTP $status ($host).', status);
        }

        final limit = truncateAt ?? maxBytes;
        final builder = BytesBuilder(copy: false);
        var truncated = false;
        try {
          await for (final chunk in response.stream.timeout(timeout)) {
            if (cancel?.isCancelled ?? false) throw const RequestCancelled();
            builder.add(chunk);
            if (builder.length >= limit) {
              truncated = true;
              break; // cancels the subscription
            }
          }
        } on TimeoutException {
          throw _TransientFailure('Réponse interrompue ($host).');
        }
        if (truncated && truncateAt == null) {
          throw SourceException('Réponse anormalement volumineuse ($host).', statusCode: status);
        }
        var bytes = builder.takeBytes();
        if (bytes.length > limit) bytes = Uint8List.sublistView(bytes, 0, limit);
        if (status < 400) breaker.recordSuccess(host);
        watch.stop();
        return EngineResponse(
          status: status,
          bytes: bytes,
          headers: response.headers,
          finalUri: current,
          truncated: truncated,
          elapsed: watch.elapsed,
        );
      } finally {
        gate.release();
      }
    }
    throw const SourceException('Trop de redirections.');
  }

  static String _short(Object e) {
    final text = '$e';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  void clearCache() => _textCache.clear();

  void close() => _client.close();
}

class _TransientFailure implements Exception {
  const _TransientFailure(this.message, [this.status]);
  final String message;
  final int? status;
}
