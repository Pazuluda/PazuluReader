import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/webview_crash_guard.dart';

void main() {
  group('Garde anti-boucle de crash WebView2', () {
    late Directory sandbox;
    late WebviewCrashGuard guard;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('pazulu-webview-');
      guard = WebviewCrashGuard(File('${sandbox.path}/nested/webview-v042-active.flag'));
    });

    tearDown(() async {
      await guard.leave();
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('plantage récent d’un autre lancement : refusé', () async {
      await guard.marker.parent.create(recursive: true);
      await guard.marker.writeAsString(WebviewCrashGuard.encode(pid + 1, DateTime.now()));
      expect(await guard.enter(), isFalse);
    });

    test('marqueur ancien d’un autre lancement (Pazulu fermé page ouverte) : autorisé', () async {
      await guard.marker.parent.create(recursive: true);
      await guard.marker.writeAsString(
          WebviewCrashGuard.encode(pid + 1, DateTime.now().subtract(const Duration(hours: 2))));
      expect(await guard.enter(), isTrue);
    });

    test('deux WebView du même lancement : autorisées, marqueur gardé jusqu’à la dernière', () async {
      final other = WebviewCrashGuard(guard.marker);
      expect(await guard.enter(), isTrue);
      expect(await other.enter(), isTrue);
      await other.leave();
      expect(await guard.marker.exists(), isTrue);
      await guard.leave();
      expect(await guard.marker.exists(), isFalse);
    });

    test('apres fermeture propre, la lecture est de nouveau autorisee', () async {
      expect(await guard.enter(), isTrue);
      await guard.leave();
      expect(await guard.marker.exists(), isFalse);
      expect(await guard.enter(), isTrue);
    });

    test('un nouvel essai explicite autorise la reprise', () async {
      await guard.marker.parent.create(recursive: true);
      await guard.marker.writeAsString(WebviewCrashGuard.encode(pid + 1, DateTime.now()));
      expect(await guard.enter(retry: true), isTrue);
    });

    test('looksLikeCrash', () {
      final now = DateTime.utc(2026, 11, 9, 15);
      expect(WebviewCrashGuard.looksLikeCrash(WebviewCrashGuard.encode(7, now), processId: 7, now: now), isFalse);
      expect(WebviewCrashGuard.looksLikeCrash(WebviewCrashGuard.encode(8, now), processId: 7, now: now), isTrue);
      expect(WebviewCrashGuard.looksLikeCrash(now.toIso8601String(), processId: 7, now: now), isTrue);
      expect(WebviewCrashGuard.looksLikeCrash('n’importe quoi', processId: 7, now: now), isFalse);
    });
  });
}
