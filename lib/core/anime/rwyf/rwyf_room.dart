import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../log.dart';

/// The background part of « Roll With Your Friends », inside Pazulu: the
/// room on the extension's sync server (socket.io), and the messages with
/// the extension script running in the Crunchyroll page.
///
/// Same protocol as the extension (rt-sync.azurewebsites.net, query
/// videoProgress / videoState / room, events « join » and « update »), so
/// a Pazulu user and Firefox users share the same rooms and links.
class RwyfRoom extends ChangeNotifier {
  RwyfRoom({required this.send, Uri? server}) : server = server ?? defaultServer;

  /// Delivers a message to the extension script of the page.
  final Future<void> Function(Map<String, Object?> message) send;

  static final Uri defaultServer = Uri.parse('https://rwyf-sync.onrender.com');

  /// The extension's sync server (updated with the extension).
  Uri server;
  static const roomParam = 'rollTogetherRoom';

  String? roomId;
  int userCount = 0;
  bool connecting = false;
  String? error;

  /// What the connection is doing (« Réveil du serveur… »), for the panel.
  String? status;

  /// Set when this Pazulu created the room (to show / copy the link).
  bool createdHere = false;
  String pageUrl = '';

  _SocketIo? _socket;
  bool _sentRequest = false;
  bool _pageConnected = false;
  ({String state, double progress, DateTime at})? _room;
  bool _disposed = false;

  bool get inRoom => roomId != null;
  bool get pageReady => _pageConnected;

  /// Link to send to friends (this episode + the room).
  String? get shareUrl {
    final id = roomId;
    if (id == null || pageUrl.isEmpty) return null;
    return withRoom(pageUrl, id);
  }

  static String withRoom(String url, String id) {
    final u = Uri.parse(url);
    final q = Map<String, String>.from(u.queryParameters)..[roomParam] = id;
    return u.replace(queryParameters: q).toString();
  }

  static String? roomOf(String url) => Uri.tryParse(url)?.queryParameters[roomParam];

  double _roomProgress() {
    final r = _room!;
    final elapsed = r.state == 'playing' ? DateTime.now().difference(r.at).inMilliseconds / 1000 : 0;
    return r.progress + elapsed;
  }

  /// Messages queued by the page script ({type: …}).
  void fromPage(Map<String, Object?> m, String url) {
    if (url.isNotEmpty) pageUrl = url;
    switch (m['type']) {
      case 'port_connection':
        _onPageConnected();
      case 'cs2w2_room_connection':
        _connect(_num(m['currentProgress']), '${m['state'] ?? 'paused'}', roomOf(pageUrl));
      case 'cs2w2_local_update':
        final s = _socket;
        if (s == null) break;
        final state = '${m['state'] ?? 'paused'}';
        final progress = _num(m['currentProgress']);
        s.emit('update', [state, progress]);
        _room = (state: state, progress: progress, at: DateTime.now());
      default:
        break; // heart beat
    }
  }

  /// A new page (first load or reload) has the extension running.
  void _onPageConnected() {
    _pageConnected = true;
    _sentRequest = false;
    if (_socket != null && roomId != null && _room != null) {
      // Reload while in a room: bring the new page back in sync.
      send({
        'type': 'sw2cs_remote_update', 'kind': 'join',
        'roomState': _room!.state, 'roomProgress': _roomProgress(), 'userCount': userCount,
      });
    } else if (roomOf(pageUrl) != null) {
      _requestConnection(); // link of a friend: join the room
    }
    notifyListeners();
  }

  /// « Créer un salon » (or join the room of the current link).
  void createRoom() {
    error = null;
    createdHere = roomOf(pageUrl) == null;
    _requestConnection();
  }

  void _requestConnection() {
    if (_sentRequest) return;
    if (_socket != null) {
      if (roomOf(pageUrl) == roomId) return;
      leave();
    }
    _sentRequest = true;
    connecting = true;
    notifyListeners();
    // The page answers with its position (cs2w2_room_connection).
    send({'type': 'sw2cs_room_connection'});
  }

  void _connect(double progress, String state, String? urlRoom) {
    if (_socket != null) return;
    final query = <String, String>{
      'videoProgress': '${progress.round()}',
      'videoState': state,
      if (urlRoom != null && urlRoom.isNotEmpty) 'room': urlRoom,
    };
    status = 'Connexion au serveur… (s’il dormait, jusqu’à 1 min)';
    notifyListeners();
    final socket = _SocketIo(server, query,
        onEvent: _onEvent,
        onClosed: (unexpected) {
          if (!unexpected || _disposed || roomId == null) return;
          // Network hiccup: back in the same room, at the room's position.
          _socket = null;
          final st = _room?.state ?? state;
          final pr = _room != null ? _roomProgress() : progress;
          Timer(const Duration(seconds: 2), () {
            if (!_disposed && _socket == null && roomId != null) _connect(pr, st, roomId);
          });
        },
        onError: (e) {
          error = 'Serveur de synchronisation injoignable ($e)';
          status = null;
          connecting = false;
          _sentRequest = false;
          _socket = null;
          notifyListeners();
        });
    _socket = socket;
    unawaited(socket.open());
  }

  void _onEvent(String event, List<Object?> args) {
    switch (event) {
      case 'join':
        final id = args.isNotEmpty ? '${args[0]}' : '';
        final state = args.length > 1 ? '${args[1]}' : 'paused';
        final progress = args.length > 2 ? _num(args[2]) : 0.0;
        final count = args.length > 3 ? _num(args[3]).round() : 1;
        final rejoin = roomId == id;
        roomId = id;
        userCount = count;
        connecting = false;
        status = null;
        _sentRequest = false;
        _room = (state: state, progress: progress, at: DateTime.now());
        AppLog.info('Roll With Your Friends : salon $id (${rejoin ? 'reconnexion' : 'rejoint'}, $count pers.)');
        send({
          'type': 'sw2cs_remote_update', 'kind': 'join', 'rejoin': rejoin,
          'roomState': state, 'roomProgress': progress, 'userCount': count,
        });
        notifyListeners();
      case 'update':
        final sender = args.isNotEmpty ? '${args[0]}' : null;
        final state = args.length > 1 ? '${args[1]}' : 'paused';
        final progress = args.length > 2 ? _num(args[2]) : 0.0;
        final count = args.length > 3 ? _num(args[3]).round() : userCount;
        if (count > 0) userCount = count;
        _room = (state: state, progress: progress, at: DateTime.now());
        send({
          'type': 'sw2cs_remote_update', 'kind': 'update',
          'roomState': state, 'roomProgress': progress, 'userCount': userCount, 'senderId': sender,
        });
        notifyListeners();
    }
  }

  /// « Quitter le salon ».
  void leave() {
    final s = _socket;
    _socket = null;
    s?.close();
    roomId = null;
    _room = null;
    userCount = 0;
    connecting = false;
    createdHere = false;
    status = null;
    _sentRequest = false;
    send({'type': 'sw2cs_room_disconnect'});
    notifyListeners();
  }

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  void dispose() {
    _disposed = true;
    final s = _socket;
    _socket = null;
    s?.close();
    super.dispose();
  }
}

/// Minimal socket.io v4 client (Engine.IO 4, WebSocket transport): what the
/// extension uses — connect with a query, receive events, emit « update ».
class _SocketIo {
  _SocketIo(this.base, this.query, {required this.onEvent, required this.onClosed, required this.onError});

  final Uri base;
  final Map<String, String> query;
  final void Function(String event, List<Object?> args) onEvent;
  final void Function(bool unexpected) onClosed;
  final void Function(Object error) onError;

  WebSocket? _ws;
  bool _closing = false;

  static Uri endpoint(Uri base, Map<String, String> query) => base.replace(
        scheme: 'wss',
        path: '/socket.io/',
        queryParameters: {'EIO': '4', 'transport': 'websocket', ...query},
      );

  /// Engine.IO / socket.io packets: « 0{…} » open, « 2 » ping, « 40 »
  /// connected, « 42[event, …] » event, « 41 » disconnect, « 44 » error.
  static (String kind, List<Object?>? event) decode(String packet) {
    if (packet.startsWith('42')) {
      final body = packet.substring(2);
      final start = body.indexOf('[');
      if (start < 0) return ('event?', null);
      final list = jsonDecode(body.substring(start));
      if (list is List && list.isNotEmpty) return ('event', list);
      return ('event?', null);
    }
    if (packet.startsWith('40')) return ('connected', null);
    if (packet.startsWith('41')) return ('disconnect', null);
    if (packet.startsWith('44')) return ('error', null);
    if (packet.startsWith('0')) return ('open', null);
    if (packet == '2') return ('ping', null);
    if (packet == '3') return ('pong', null);
    if (packet.startsWith('1')) return ('close', null);
    return ('other', null);
  }

  static String encodeEvent(String event, List<Object?> args) => '42${jsonEncode([event, ...args])}';

  /// Free hosting (Render) puts the server to sleep after 15 min: a plain
  /// HTTP request wakes it (up to ~1 min) before the WebSocket is opened.
  static Future<void> wake(Uri base) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(base.replace(path: '/'));
      final res = await req.close().timeout(const Duration(seconds: 90));
      await res.drain<void>();
    } catch (_) {
      // the WebSocket attempt below says what is wrong
    } finally {
      client.close(force: true);
    }
  }

  Future<void> open() async {
    try {
      final url = endpoint(base, query).toString();
      await wake(base);
      WebSocket ws;
      try {
        ws = await WebSocket.connect(url).timeout(const Duration(seconds: 45));
      } on SocketException catch (e) {
        // Windows' DNS does not know the server (box / ISP DNS): resolve it
        // with DNS over HTTPS, then connect to that address (TLS still
        // checked against the real host name).
        if (!_isLookupFailure(e)) rethrow;
        final ip = await resolveOverHttps(base.host);
        AppLog.info('Roll With Your Friends : DNS Windows en échec, ${base.host} → $ip (DNS sécurisé)');
        final client = HttpClient()
          ..connectionFactory = (uri, proxyHost, proxyPort) async => ConnectionTask.fromSocket(
              Socket.connect(ip, uri.port == 0 ? 443 : uri.port, timeout: const Duration(seconds: 15))
                  .then((raw) => SecureSocket.secure(raw, host: uri.host)),
              () {});
        ws = await WebSocket.connect(url, customClient: client).timeout(const Duration(seconds: 45));
      }
      _ws = ws;
      ws.listen((data) {
        if (data is! String) return;
        final (kind, ev) = decode(data);
        switch (kind) {
          case 'open':
            ws.add('40'); // join the default namespace
          case 'ping':
            ws.add('3');
          case 'event':
            onEvent('${ev![0]}', ev.sublist(1));
          case 'error':
            onError('refus du serveur');
          case 'disconnect' || 'close':
            _closing = true;
            ws.close();
            onClosed(false);
        }
      }, onDone: () {
        if (!_closing) onClosed(true);
      }, onError: (Object e) {
        if (!_closing) onClosed(true);
      }, cancelOnError: true);
    } catch (e) {
      onError(e);
    }
  }

  static bool _isLookupFailure(SocketException e) {
    final m = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    return m.contains('host lookup') || m.contains('hôte inconnu') || m.contains('no such host') ||
        e.osError?.errorCode == 11001 || e.osError?.errorCode == 11004;
  }

  /// A (IPv4) address of [host] from Cloudflare, then Google, over HTTPS.
  /// Throws a clear message when the name does not exist anymore.
  static Future<String> resolveOverHttps(String host) async {
    final providers = [
      Uri.https('cloudflare-dns.com', '/dns-query', {'name': host, 'type': 'A'}),
      Uri.https('dns.google', '/resolve', {'name': host, 'type': 'A'}),
    ];
    Object? last;
    for (final u in providers) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(u);
        req.headers.set('Accept', 'application/dns-json');
        final res = await req.close().timeout(const Duration(seconds: 10));
        final body = await res.transform(utf8.decoder).join();
        final ip = parseDnsJson(body);
        if (ip != null) return ip;
        final st = _dnsStatus(body);
        AppLog.info('Roll With Your Friends : ${u.host} répond pour $host : '
            '${body.length > 300 ? body.substring(0, 300) : body}');
        last = st == 3 ? 'nom inconnu' : 'pas d’adresse (statut DNS $st)';
      } catch (e) {
        last = e;
      } finally {
        client.close(force: true);
      }
    }
    if (last == 'nom inconnu') {
      throw 'le serveur $host n’existe plus (nom de domaine introuvable, même via Cloudflare et Google)';
    }
    throw 'adresse de $host introuvable ($last)';
  }

  static int? _dnsStatus(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map && j['Status'] is int ? j['Status'] as int : null;
    } catch (_) {
      return null;
    }
  }

  /// First IPv4 answer of a DNS JSON reply (Cloudflare / Google format).
  static String? parseDnsJson(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['Status'] != 0) return null;
    final answers = j['Answer'];
    if (answers is! List) return null;
    for (final a in answers) {
      if (a is Map && a['type'] == 1 && a['data'] is String &&
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(a['data'] as String)) {
        return a['data'] as String;
      }
    }
    return null;
  }

  void emit(String event, List<Object?> args) {
    try {
      _ws?.add(encodeEvent(event, args));
    } catch (_) {}
  }

  void close() {
    _closing = true;
    try {
      _ws?.add('41');
    } catch (_) {}
    _ws?.close();
  }
}

@visibleForTesting
(String, List<Object?>?) decodeSocketIoPacket(String p) => _SocketIo.decode(p);

@visibleForTesting
String encodeSocketIoEvent(String e, List<Object?> a) => _SocketIo.encodeEvent(e, a);

@visibleForTesting
String? parseDnsJsonAnswer(String body) => _SocketIo.parseDnsJson(body);

@visibleForTesting
Uri socketIoEndpoint(Map<String, String> q) => _SocketIo.endpoint(RwyfRoom.defaultServer, q);
