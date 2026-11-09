import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/app_update.dart';

void main() {
  test('versions : comparaison', () {
    expect(AppUpdater.compareVersions('v2.4.1', '2.4.0'), greaterThan(0));
    expect(AppUpdater.compareVersions('2.4.0', '2.4.0'), 0);
    expect(AppUpdater.compareVersions('2.10.0', '2.9.9'), greaterThan(0));
    expect(AppUpdater.compareVersions('Pazulu 2.3.25', '2.4.0'), lessThan(0));
  });

  test('release GitHub plus récente avec ZIP Windows', () {
    const body = '''
{"tag_name":"v2.4.2","name":"Pazulu 2.4.2","draft":false,"prerelease":false,
 "body":"- Corrections","published_at":"2026-11-10T10:00:00Z","html_url":"https://github.com/a/b/releases/tag/v2.4.2",
 "assets":[{"name":"PazuluReader-2.4.2-Source.zip","browser_download_url":"https://x/src.zip","size":400000},
           {"name":"PazuluReader-2.4.2-windows.zip","browser_download_url":"https://x/win.zip","size":23000000}]}''';
    final u = AppUpdater.parseRelease(body, '2.4.1');
    expect(u, isNotNull);
    expect(u!.version, '2.4.2');
    expect(u.zipUrl, 'https://x/win.zip');
    expect(u.notes, '- Corrections');
    expect(AppUpdater.parseRelease(body, '2.4.2'), isNull);
    expect(AppUpdater.parseRelease(body.replaceFirst('"prerelease":false', '"prerelease":true'), '2.4.1'), isNull);
  });

  test('dépôt : format propriétaire/dépôt seulement', () {
    expect(AppUpdater.validRepo('liam/pazulu-reader'), isTrue);
    expect(AppUpdater.validRepo(''), isFalse);
    expect(AppUpdater.validRepo('https://github.com/liam/pazulu'), isFalse);
  });

  test('script d’installation : attend, décompresse, copie, relance', () {
    final s = AppUpdater.installScript(zip: r'C:\T\u.zip', appDir: r'C:\App', exe: 'pazulu_reader.exe', pid: 4242);
    expect(s, contains('PID eq 4242'));
    expect(s, contains(r'$env:ZIP'));
    expect(s, contains('robocopy "%SRC%" "%DST%"'));
    expect(s, contains(r'start "" "%DST%\pazulu_reader.exe"'));
  });
}
