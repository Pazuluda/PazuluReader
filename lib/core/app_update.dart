import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A newer Pazulu Reader published on GitHub (Releases).
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.notes,
    required this.zipUrl,
    required this.zipName,
    required this.size,
    this.publishedAt,
    this.pageUrl,
    this.setupUrl,
    this.setupName,
    this.setupSize = 0,
  });

  /// Official installer of the release (« PazuluReader-X.Y.Z-setup.exe »).
  final String? setupUrl;
  final String? setupName;
  final int setupSize;

  final String version;
  final String notes;
  final String zipUrl;
  final String zipName;
  final int size;
  final DateTime? publishedAt;
  final String? pageUrl;
}

/// Mises à jour de l'application, comme Aurore : la dernière « Release »
/// d'un dépôt GitHub public est comparée à la version installée. Rien n'est
/// téléchargé sans un clic ; aucun serveur obligatoire (sans dépôt
/// configuré, la fonction reste simplement inactive).
///
/// Installation : le ZIP Windows de la release est téléchargé dans le
/// dossier temporaire, puis un petit script invisible attend la fermeture de Pazulu,
/// décompresse, remplace les fichiers du dossier de l'application et
/// relance Pazulu. Les données (bibliothèque, progression, réglages) sont
/// dans %APPDATA% : elles ne sont jamais touchées.
class AppUpdater {
  AppUpdater({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'PazuluReader-Updater',
  };

  /// « owner/repo » valide (rien d'autre n'est appelé).
  static bool validRepo(String repo) => RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo.trim());

  /// « v2.4.1 », « 2.4.1+71 », « Pazulu 2.4.1 » → [2, 4, 1].
  static List<int> versionParts(String raw) {
    final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(raw);
    if (m == null) return const [0, 0, 0];
    return [for (var i = 1; i <= 3; i++) int.tryParse(m[i] ?? '0') ?? 0];
  }

  /// > 0 when [a] is newer than [b].
  static int compareVersions(String a, String b) {
    final x = versionParts(a);
    final y = versionParts(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }

  /// The release when it is newer than [current] and has a Windows ZIP.
  static AppUpdateInfo? parseRelease(String body, String current) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = '${json['tag_name'] ?? json['name'] ?? ''}';
    if (tag.isEmpty || compareVersions(tag, current) <= 0) return null;
    final assets = json['assets'];
    if (assets is! List) return null;
    Map? zip;
    Map? setup;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = '${a['name'] ?? ''}'.toLowerCase();
      if (name.endsWith('-setup.exe') && a['browser_download_url'] is String) setup = a;
      if (!name.endsWith('.zip')) continue;
      // The Windows build first (« PazuluReader-2.4.1-windows.zip »).
      if (name.contains('windows') || zip == null) zip = a;
    }
    if (zip == null || zip['browser_download_url'] is! String) return null;
    final parts = versionParts(tag);
    return AppUpdateInfo(
      version: parts.join('.'),
      notes: '${json['body'] ?? ''}'.trim(),
      zipUrl: zip['browser_download_url'] as String,
      zipName: '${zip['name']}',
      size: zip['size'] is int ? zip['size'] as int : 0,
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      pageUrl: json['html_url'] is String ? json['html_url'] as String : null,
      setupUrl: setup?['browser_download_url'] as String?,
      setupName: setup == null ? null : '${setup['name']}',
      setupSize: setup?['size'] is int ? setup!['size'] as int : 0,
    );
  }

  Future<AppUpdateInfo?> check(String repo, String current) async {
    if (!validRepo(repo)) return null;
    final uri = Uri.https('api.github.com', '/repos/${repo.trim()}/releases/latest');
    final r = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 404) return null; // no release yet
    if (r.statusCode != 200) throw 'GitHub HTTP ${r.statusCode}';
    return parseRelease(utf8.decode(r.bodyBytes), current);
  }

  static Directory get workDir =>
      Directory('${Directory.systemTemp.path}${Platform.pathSeparator}pazulu-update');

  /// Pazulu was installed with the official installer (its uninstaller is
  /// next to the program): the update then uses the release's installer,
  /// which closes Pazulu, replaces the files where they are and restarts
  /// it, without any window. Otherwise (portable folder) the ZIP is used.
  static bool installedWithSetup() {
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      return File('${dir.path}${Platform.pathSeparator}unins000.exe').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Downloads the update into %TEMP%\pazulu-update (progress 0..1): the
  /// installer when [useSetup], otherwise the ZIP.
  Future<File> download(AppUpdateInfo info, {void Function(double)? onProgress, bool useSetup = false}) async {
    final setup = useSetup && info.setupUrl != null;
    final url = setup ? info.setupUrl! : info.zipUrl;
    final name = setup ? (info.setupName ?? 'PazuluReader-setup.exe') : info.zipName;
    final dir = workDir;
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${name.replaceAll(RegExp(r'[^\w.\-]'), '_')}');
    final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'PazuluReader-Updater';
    final res = await _client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw 'Téléchargement refusé (HTTP ${res.statusCode})';
    final total = res.contentLength ?? (setup ? info.setupSize : info.size);
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    if (got < 1024 * 1024) throw 'Fichier de mise à jour incomplet (${got ~/ 1024} Ko)';
    return file;
  }

  /// PowerShell script, run hidden: waits for Pazulu to close (and closes
  /// that one process itself after 15 s if it lingers), unzips, copies over
  /// the app folder, starts Pazulu again. Only PowerShell commands, no
  /// console program: no black window opens. Errors go to update.log next
  /// to the downloaded file, and Pazulu restarts in its current version.
  static String installScript({required String zip, required String appDir, required String exe, required int pid}) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    return [
      r"$ErrorActionPreference = 'Stop'",
      '\$zip = ${q(zip)}',
      '\$dst = ${q(appDir)}',
      '\$exe = ${q(exe)}',
      '\$appPid = $pid',
      r"$work = Split-Path -Parent $zip",
      r"$tmp = Join-Path $work 'extracted'",
      r"$log = Join-Path $work 'update.log'",
      'try {',
      r"  $p = Get-Process -Id $appPid -ErrorAction SilentlyContinue",
      r"  if ($p -and -not $p.WaitForExit(15000)) {",
      r"    Stop-Process -Id $appPid -Force -ErrorAction SilentlyContinue",
      r"    $p.WaitForExit(5000) | Out-Null",
      '  }',
      '  Start-Sleep -Milliseconds 700',
      r"  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }",
      r"  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force",
      r"  $src = $tmp",
      r"  if (-not (Test-Path -LiteralPath (Join-Path $src $exe))) {",
      r"    $d = Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $exe) } | Select-Object -First 1",
      r"    if ($d) { $src = $d.FullName }",
      '  }',
      r"  if (-not (Test-Path -LiteralPath (Join-Path $src $exe))) { throw 'Programme absent du ZIP.' }",
      '  for (\$i = 0; \$i -lt 10; \$i++) {',
      '    try {',
      r"      Get-ChildItem -LiteralPath $src | Copy-Item -Destination $dst -Recurse -Force",
      '      break',
      '    } catch {',
      r"      if ($i -ge 9) { throw }",
      '      Start-Sleep -Seconds 1',
      '    }',
      '  }',
      r"  Add-Content -LiteralPath $log -Value ((Get-Date -Format s) + ' mise a jour installee')",
      '} catch {',
      r"  Add-Content -LiteralPath $log -Value ((Get-Date -Format s) + ' echec : ' + $_)",
      '}',
      r"Start-Process -FilePath (Join-Path $dst $exe) -WorkingDirectory $dst",
      '',
    ].join('\r\n');
  }

  /// Runs the official installer silently (no window): it waits for Pazulu
  /// to close (closing it if needed), installs in the same folder and
  /// restarts it.
  Future<void> launchSetup(File setup) async {
    await Process.start(setup.path, [
      '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCANCEL', '/SP-',
      '/CLOSEAPPLICATIONS', '/LOG=${workDir.path}${Platform.pathSeparator}setup.log',
    ], mode: ProcessStartMode.detached, runInShell: false);
  }

  /// Remembers which version is being installed: if Pazulu restarts in the
  /// old version, the install failed and it is not downloaded again in a
  /// loop.
  static File get _pendingFile => File('${workDir.path}${Platform.pathSeparator}pending.json');

  static Future<void> markPending(String version) async {
    try {
      await workDir.create(recursive: true);
      await _pendingFile.writeAsString(jsonEncode({'version': version, 'at': DateTime.now().toIso8601String()}));
    } catch (_) {}
  }

  /// The version whose install just failed (Pazulu restarted older), with
  /// the end of the install logs; null otherwise. Clears the marker.
  static Future<(String, String)?> failedInstall(String current) async {
    try {
      final f = _pendingFile;
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      await f.delete();
      if (raw is! Map) return null;
      final v = '${raw['version']}';
      final at = DateTime.tryParse('${raw['at']}');
      if (at == null || DateTime.now().difference(at) > const Duration(hours: 6)) return null;
      if (compareVersions(v, current) <= 0) return null; // installed fine
      final logs = StringBuffer();
      for (final name in ['update.log', 'setup.log']) {
        final l = File('${workDir.path}${Platform.pathSeparator}$name');
        if (await l.exists()) {
          final text = await l.readAsString();
          logs.writeln('--- $name');
          logs.writeln(text.length > 3000 ? text.substring(text.length - 3000) : text);
        }
      }
      return (v, logs.toString());
    } catch (_) {
      return null;
    }
  }

  /// Starts the install script, hidden and detached. The caller then quits
  /// Pazulu.
  Future<void> launchInstaller(File zip) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final exe = exePath.split(Platform.pathSeparator).last;
    final script = File('${zip.parent.path}${Platform.pathSeparator}installer.ps1');
    // UTF-8 with BOM: Windows PowerShell 5 reads accented paths correctly.
    await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(installScript(zip: zip.path, appDir: appDir, exe: exe, pid: pid))]);
    await Process.start('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
      '-File', script.path,
    ], mode: ProcessStartMode.detached, runInShell: false);
  }
}
