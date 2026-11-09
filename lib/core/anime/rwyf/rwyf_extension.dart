import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../engine/http/engine_http.dart';
import '../../app_update.dart';
import '../../log.dart';
import 'zip_entry.dart';

/// « Roll With Your Friends » (addons.mozilla.org), kept up to date.
///
/// Pazulu takes the newest published version (Mozilla or the author's
/// GitHub releases, checked each time the player opens, at most every 15
/// min) and the sync server of the repository; it keeps only the page script
/// (content_script.js), run inside the Crunchyroll page of the built-in
/// player. The extension gets no access to files, nor to anything outside
/// that page: its messages go through Pazulu ([RwyfRoom]).
class RwyfExtension {
  const RwyfExtension({required this.version, required this.contentScript, this.server});

  final String version;
  final String contentScript;

  /// Sync server written in the extension (its SYNC_SERVER). Read from each
  /// new version: if the extension moves to another server, Pazulu follows.
  final Uri? server;

  static final Uri defaultServer = Uri.parse('https://rwyf-sync.onrender.com');

  /// The old Roll Together server (rt-sync.azurewebsites.net) is gone since
  /// November 2026: versions that still name it use the new one.
  Uri get syncServer {
    final s = server;
    if (s == null || s.host == 'rt-sync.azurewebsites.net') return defaultServer;
    return s;
  }

  /// « const serverUrl = "https://…" » in the extension's background script.
  static Uri? serverIn(String serviceWorker) {
    final m = RegExp(r'''serverUrl\s*=\s*["'](https://[^"'\s]+)["']''').firstMatch(serviceWorker) ??
        RegExp(r'''SYNC_SERVER["']?\s*[:=]\s*["'](https://[^"'\s]+)["']''').firstMatch(serviceWorker);
    final u = m == null ? null : Uri.tryParse(m[1]!);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
  }

  static const slug = 'roll-with-your-friends';
  static final Uri apiUri = Uri.parse('https://addons.mozilla.org/api/v5/addons/addon/$slug/');

  /// The author's repository: GitHub releases (often ahead of Mozilla's
  /// review) and env.json (the sync server, followed right away).
  static const repo = 'Pazuluda/roll_with_your_friends';
  static final Uri releaseUri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
  static final Uri envUri = Uri.parse('https://raw.githubusercontent.com/$repo/main/env.json');

  static const _hosts = [
    'addons.mozilla.org', 'mozilla.net', 'mozilla.org', 'mozgcp.net',
    'api.github.com', 'github.com', 'githubusercontent.com',
  ];

  /// Checked each time the player opens, at most every 15 minutes.
  static const checkEvery = Duration(minutes: 15);

  static RwyfExtension? _memory;
  static Future<RwyfExtension?>? _refreshing;

  /// The extension to use now: checked for a newer version / server (at
  /// most every [checkEvery]), the cached one when offline or slow; the very
  /// first time, Pazulu waits for the download.
  static Future<RwyfExtension?> load(EngineHttpClient http, Directory supportDir,
      {bool force = false}) async {
    final store = _Store(Directory('${supportDir.path}${Platform.pathSeparator}rwyf'));
    final cached = _memory ?? await store.read();
    final checkedAt = await store.checkedAt();
    final due = force || cached == null || checkedAt == null ||
        DateTime.now().difference(checkedAt) >= checkEvery;
    if (!due) return _memory = cached;
    final refresh = _refreshing ??= _refresh(http, store, cached).whenComplete(() => _refreshing = null);
    if (cached == null) return _memory = await refresh;
    // A few seconds for the check (a new server or version is used right
    // away); slow network: the cached version now, the new one next time.
    try {
      return _memory = (await refresh.timeout(const Duration(seconds: 6))) ?? cached;
    } on TimeoutException {
      unawaited(refresh.then((e) {
        if (e != null) _memory = e;
      }));
      return _memory = cached;
    }
  }

  /// Newest published version between Mozilla and GitHub releases, and the
  /// server of the repository's env.json.
  static Future<RwyfExtension?> _refresh(EngineHttpClient http, _Store store, RwyfExtension? cached) async {
    var current = cached;
    try {
      final candidates = <({String version, Uri url, String source})>[];
      try {
        final r = await http.get(apiUri, allowedHosts: _hosts, timeout: const Duration(seconds: 15),
            headers: const {'Accept': 'application/json'});
        if (r.ok) {
          final cur = (jsonDecode(r.text) as Map)['current_version'] as Map;
          candidates.add((version: '${cur['version']}', url: Uri.parse('${(cur['file'] as Map)['url']}'),
              source: 'Mozilla'));
        }
      } catch (e) {
        AppLog.info('Roll With Your Friends : Mozilla injoignable ($e)');
      }
      try {
        final r = await http.get(releaseUri, allowedHosts: _hosts, timeout: const Duration(seconds: 15),
            headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'PazuluReader'});
        if (r.ok) {
          final rel = releaseFromJson(r.text);
          if (rel != null) candidates.add((version: rel.version, url: rel.url, source: 'GitHub'));
        }
      } catch (_) {
        // no release yet: Mozilla only
      }
      Uri? repoServer;
      try {
        final r = await http.get(envUri, allowedHosts: _hosts, timeout: const Duration(seconds: 15));
        if (r.ok) repoServer = serverInEnv(r.text);
      } catch (_) {}

      final best = newest(candidates);
      if (best != null && (current == null || AppUpdater.compareVersions(best.version, current.version) > 0)) {
        final x = await http.get(best.url, allowedHosts: _hosts, timeout: const Duration(seconds: 40),
            headers: const {'User-Agent': 'PazuluReader', 'Accept': 'application/octet-stream'});
        if (!x.ok) throw 'téléchargement refusé (HTTP ${x.status})';
        final cs = zipEntry(x.bytes, 'content_script.js');
        if (cs == null) throw 'content_script.js absent de la version ${best.version}';
        final sw = zipEntry(x.bytes, 'service_worker.js');
        current = RwyfExtension(
          version: best.version,
          contentScript: utf8.decode(cs, allowMalformed: true),
          server: sw == null ? null : serverIn(utf8.decode(sw, allowMalformed: true)),
        );
        await store.writeScript(current.contentScript);
        AppLog.info('Roll With Your Friends ${best.version} (${best.source}) installé dans le lecteur Crunchyroll');
      }
      if (current != null && repoServer != null && repoServer != current.server) {
        current = RwyfExtension(version: current.version, contentScript: current.contentScript, server: repoServer);
        AppLog.info('Roll With Your Friends : serveur ${repoServer.host} (dépôt de l’extension)');
      }
      if (current != null) await store.writeMeta(current);
    } catch (e) {
      AppLog.info('Roll With Your Friends : mise à jour impossible ($e)'
          '${current == null ? '' : ', version ${current.version} gardée'}');
    }
    return current;
  }

  /// Highest version (Mozilla wins a tie: reviewed build).
  static ({String version, Uri url, String source})? newest(
      List<({String version, Uri url, String source})> list) {
    ({String version, Uri url, String source})? best;
    for (final c in list) {
      if (best == null || AppUpdater.compareVersions(c.version, best.version) > 0) best = c;
    }
    return best;
  }

  /// GitHub « latest release » with the Firefox package.
  static ({String version, Uri url})? releaseFromJson(String body) {
    final j = jsonDecode(body);
    if (j is! Map || j['draft'] == true || j['prerelease'] == true) return null;
    final assets = j['assets'];
    if (assets is! List) return null;
    for (final a in assets) {
      if (a is Map && '${a['name']}'.toLowerCase().contains('firefox') &&
          '${a['name']}'.toLowerCase().endsWith('.zip') && a['browser_download_url'] is String) {
        final parts = AppUpdater.versionParts('${j['tag_name'] ?? j['name'] ?? ''}');
        return (version: parts.join('.'), url: Uri.parse(a['browser_download_url'] as String));
      }
    }
    return null;
  }

  /// env.json of the repository: production SYNC_SERVER (https only).
  static Uri? serverInEnv(String body) {
    try {
      final j = jsonDecode(body);
      final v = j is Map && j['production'] is Map ? (j['production'] as Map)['SYNC_SERVER'] : null;
      final u = v is String ? Uri.tryParse(v.trim()) : null;
      return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
    } catch (_) {
      return null;
    }
  }

  /// Bridge given to the page before the extension script: it stands in for
  /// the browser's extension messaging (the only API the page script uses)
  /// and queues the messages for Pazulu.
  static const shim = r'''
(function(){
  if (window.__pazuluRwyf) return;
  var listeners = [], outbox = [];
  var port = {
    name: 'content_script',
    postMessage: function (m) { outbox.push(m); },
    onMessage: { addListener: function (f) { listeners.push(f); } },
    onDisconnect: { addListener: function () {} },
    disconnect: function () {}
  };
  window.addEventListener('error', function (e) {
    outbox.push({type: 'pz_error', message: String((e && e.message) || e).slice(0, 300)});
  });
  window.addEventListener('unhandledrejection', function (e) {
    outbox.push({type: 'pz_error', message: ('promesse : ' + String(e && e.reason)).slice(0, 300)});
  });
  window.__pazuluRwyf = {
    take: function () { var o = outbox; outbox = []; return JSON.stringify({u: location.href, m: o}); },
    deliver: function (m) { for (var i = 0; i < listeners.length; i++) { try { listeners[i](m); } catch (e) {} } }
  };
  var noop = function () {};
  var store = { get: function (d, cb) { var v = (d && typeof d === 'object') ? d : {}; if (cb) cb(v); return Promise.resolve(v); }, set: function (v, cb) { if (cb) cb(); return Promise.resolve(); } };
  window.browser = {
    runtime: {
      connect: function () { outbox.push({type: 'port_connection'}); return port; },
      getManifest: function () { return {manifest_version: 3}; },
      onMessage: { addListener: noop }
    },
    storage: { sync: store, local: store },
    tabs: {}
  };
})();
''';

  /// Script run in the page: bridge + extension, only on crunchyroll.com
  /// and only once per page.
  String injection() => '''
(function(){
  if (!/(^|\\.)crunchyroll\\.com\$/.test(location.hostname)) return 'off';
  if (window.__pazuluRwyf) return 'on';
  $shim
  try {
$contentScript
  } catch (e) { return 'error:' + e; }
  return 'injected';
})()''';
}

class _Store {
  _Store(this.dir);

  final Directory dir;

  File get _script => File('${dir.path}${Platform.pathSeparator}content_script.js');
  File get _meta => File('${dir.path}${Platform.pathSeparator}version.json');

  Future<Map?> _readMeta() async {
    try {
      if (!await _meta.exists()) return null;
      final m = jsonDecode(await _meta.readAsString());
      return m is Map ? m : null;
    } catch (_) {
      return null;
    }
  }

  Future<RwyfExtension?> read() async {
    final m = await _readMeta();
    if (m == null || !await _script.exists()) return null;
    try {
      return RwyfExtension(
        version: '${m['version']}',
        contentScript: await _script.readAsString(),
        server: m['server'] is String ? Uri.tryParse(m['server'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> checkedAt() async => DateTime.tryParse('${(await _readMeta())?['checkedAt']}');

  Future<void> writeScript(String js) async {
    await dir.create(recursive: true);
    await _script.writeAsString(js, flush: true);
  }

  Future<void> writeMeta(RwyfExtension e) async {
    await dir.create(recursive: true);
    await _meta.writeAsString(jsonEncode({
      'version': e.version,
      'checkedAt': DateTime.now().toIso8601String(),
      if (e.server != null) 'server': e.server.toString(),
    }));
  }
}
