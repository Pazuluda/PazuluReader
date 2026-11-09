import 'dart:convert';
import 'dart:io';

import 'user_sources.dart';

/// Availability is not copyright permission nor proof the reader/extractor works.
/// A failed HTTP probe is never sufficient to conclude that a site has closed.
enum SourceHealthStatus {
  unknown, reachable, blocked, unstable, suspectedOffline,
}

class SourceProbeResult {
  const SourceProbeResult({
    required this.checkedAt,
    this.httpStatus,
    this.error,
    this.redirectHost,
    this.isHtml = false,
    this.challenge = false,
  });

  final DateTime checkedAt;
  final int? httpStatus;
  final String? error;
  final String? redirectHost;
  final bool isHtml;
  final bool challenge;
}

class SourceHealth {
  const SourceHealth({
    required this.id,
    required this.status,
    required this.checkedAt,
    this.lastReachableAt,
    this.firstFailureAt,
    this.failures = 0,
    this.httpStatus,
    this.note,
  });

  final String id;
  final SourceHealthStatus status;
  final DateTime checkedAt;
  final DateTime? lastReachableAt;
  final DateTime? firstFailureAt;
  final int failures;
  final int? httpStatus;
  final String? note;

  bool get suspectedDead => status == SourceHealthStatus.suspectedOffline;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'checkedAt': checkedAt.toIso8601String(),
    'lastReachableAt': lastReachableAt?.toIso8601String(),
    'firstFailureAt': firstFailureAt?.toIso8601String(),
    'failures': failures,
    'httpStatus': httpStatus,
    'note': note,
  };

  factory SourceHealth.fromJson(Map<String, dynamic> data) {
    final status = SourceHealthStatus.values.firstWhere(
      (v) => v.name == data['status'],
      orElse: () => SourceHealthStatus.unknown,
    );
    final id = data['id'];
    final at = DateTime.tryParse(data['checkedAt']?.toString() ?? '');
    if (id is! String || id.isEmpty || at == null) {
      throw const FormatException('Historique de verification invalide.');
    }
    DateTime? optionalDate(String key) => DateTime.tryParse(data[key]?.toString() ?? '');
    final errors = data['failures'];
    return SourceHealth(
      id: id, status: status, checkedAt: at,
      lastReachableAt: optionalDate('lastReachableAt'),
      firstFailureAt: optionalDate('firstFailureAt'),
      failures: errors is int && errors >= 0 ? errors : 0,
      httpStatus: data['httpStatus'] is int ? data['httpStatus'] as int : null,
      note: data['note'] is String ? data['note'] as String : null,
    );
  }
}

/// Observations accumulate, with a minimum 24-hour window for 'suspected'.
/// Blocks (403/429), login/challenge pages and redirected hosts are *not* outages.
SourceHealth observeSourceHealth(String id, SourceHealth? old, SourceProbeResult probe) {
  final status = probe.httpStatus;
  final isRedirect = probe.redirectHost != null;
  final reachable = status != null && status >= 200 && status < 400 &&
      probe.isHtml && !probe.challenge && !isRedirect;
  if (reachable) {
    return SourceHealth(
      id: id, status: SourceHealthStatus.reachable,
      checkedAt: probe.checkedAt, lastReachableAt: probe.checkedAt,
      httpStatus: status, note: 'Le site repond ; lecture a tester.',
    );
  }
  final blocked = status == 401 || status == 403 || status == 407 ||
      status == 429 || probe.challenge || isRedirect;
  if (blocked) {
    return SourceHealth(
      id: id, status: SourceHealthStatus.blocked,
      checkedAt: probe.checkedAt, lastReachableAt: old?.lastReachableAt,
      firstFailureAt: null, failures: 0,
      httpStatus: status,
      note: isRedirect ? 'Redirection vers ${probe.redirectHost} : verifier le domaine.' :
          probe.challenge ? 'Page de verification ou de maintenance.' :
          'Acces limite depuis la verification ; essayer dans la vue integree.',
    );
  }
  final priorFailure = old?.firstFailureAt ?? probe.checkedAt;
  final failures = (old?.failures ?? 0) + 1;
  final suspected = failures >= 3 &&
      probe.checkedAt.difference(priorFailure) >= const Duration(hours: 24);
  return SourceHealth(
    id: id,
    status: suspected ? SourceHealthStatus.suspectedOffline : SourceHealthStatus.unstable,
    checkedAt: probe.checkedAt, lastReachableAt: old?.lastReachableAt,
    firstFailureAt: priorFailure, failures: failures,
    httpStatus: status,
    note: probe.error ??
      (status == 525 ? 'Erreur SSL 525 entre Cloudflare et le site.' :
       status == null ? 'Le serveur ne repond pas.' :
       'Reponse HTTP $status.'),
  );
}

/// Normal probes, not stealth browsing or authentication circumvention.
/// Redirects to other hosts are reported rather than silently followed.
class SourceHealthProbe {
  const SourceHealthProbe({this.timeout = const Duration(seconds: 7)});
  final Duration timeout;

  Future<SourceProbeResult> check(String url) async {
    final now = DateTime.now();
    Uri uri;
    try {
      uri = normalizedSourceUri(url);
    } catch (e) {
      return SourceProbeResult(checkedAt: now, error: 'Adresse invalide : $e');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    client.userAgent = 'PazuluReader/0.4.6 (availability check)';
    try {
      final addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
      if (addresses.isEmpty || addresses.any(isNonPublicIpAddress)) {
        return SourceProbeResult(checkedAt: now, error: 'Adresse reseau non publique.');
      }
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      final response = await request.close().timeout(timeout);
      final code = response.statusCode;
      String? redirectHost;
      if (code >= 300 && code < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final target = location == null ? null : uri.resolve(location);
        if (target != null && target.host.toLowerCase() != uri.host.toLowerCase()) {
          redirectHost = target.host;
        }
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      final isHtml = contentType == 'text/html' ||
          contentType == 'application/xhtml+xml' || (code >= 300 && code < 400);
      // Read only the first response chunk, never the full site or chapters.
      // A 200 response containing a bot challenge is not proof of availability.
      var challenge = false;
      if (code == 200 && isHtml) {
        try {
          final bytes = await response.first.timeout(timeout);
          final snippet = utf8.decode(bytes.take(12000).toList(),
              allowMalformed: true).toLowerCase();
          challenge = (snippet.contains('cloudflare') &&
              snippet.contains('just a moment')) ||
              snippet.contains('checking your browser') ||
              snippet.contains('we are under maintenance') ||
              snippet.contains("we're upgrading our website");
        } catch (_) {
          // Empty/slow body: headers alone are not a chapter-readability test.
        }
      }
      return SourceProbeResult(
        checkedAt: DateTime.now(), httpStatus: code,
        isHtml: isHtml, challenge: challenge,
        redirectHost: redirectHost,
      );
    } catch (error) {
      return SourceProbeResult(checkedAt: DateTime.now(), error: '$error');
    } finally {
      client.close(force: true);
    }
  }
}

bool isNonPublicIpAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) return true;
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && b.length == 4) {
    return b[0] == 0 || b[0] == 10 || b[0] == 127 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 192 && b[1] == 0 && b[2] == 0) ||
        (b[0] >= 224);
  }
  if (address.type == InternetAddressType.IPv6 && b.length == 16) {
    return (b[0] & 0xfe) == 0xfc || b.every((n) => n == 0);
  }
  return false;
}

class SourceHealthStore {
  SourceHealthStore(this.file);
  final File file;

  static Map<String, SourceHealth> decode(String text) {
    if (text.length > 200000) throw const FormatException('Historique trop volumineux.');
    final value = jsonDecode(text);
    if (value is! Map || value['format'] != 'pazulu-source-health' ||
        value['schemaVersion'] != 1 || value['sources'] is! List ||
        (value['sources'] as List).length > 150) {
      throw const FormatException('Historique source invalide.');
    }
    final items = <String, SourceHealth>{};
    for (final raw in value['sources'] as List) {
      if (raw is! Map<String, dynamic>) throw const FormatException('Entree incorrecte.');
      final item = SourceHealth.fromJson(raw);
      if (items.containsKey(item.id)) throw const FormatException('Doublon dans les historiques.');
      items[item.id] = item;
    }
    return items;
  }

  static String encode(Iterable<SourceHealth> items) => const JsonEncoder.withIndent('  ').convert({
    'format': 'pazulu-source-health', 'schemaVersion': 1,
    'sources': items.map((e) => e.toJson()).toList(),
  });

  Future<Map<String, SourceHealth>> load() async {
    if (!await file.exists()) return {};
    return decode(await file.readAsString());
  }

  Future<void> save(Iterable<SourceHealth> items) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encode(items), flush: true);
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}
