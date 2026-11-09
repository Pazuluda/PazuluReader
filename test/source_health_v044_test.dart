import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/source_health.dart';
import 'package:pazulu_reader/core/source_extensions.dart';
import 'package:pazulu_reader/core/user_sources.dart';

void main() {
  final today = DateTime.utc(2026, 11, 5, 12);

  test('13 sources are active, two legacy ones remain addressable', () {
    expect(catalogSites.length, 13);
    expect(catalogSites.any((s) => s.id == 'manhuafast'), isFalse);
    expect(catalogSites.any((s) => s.id == 'manhwaclan'), isFalse);
    expect(catalogSiteById('manhuafast'), isNotNull);
    expect(catalogSiteById('manhwaclan'), isNotNull);
    expect(SourceRecipeRegistry.defaults().forSite('manhwaclan').mode,
        'inspect');
  });

  test('a user can add a public source with only an URL', () {
    final source = createUserSource(
      url: 'https://sample-reader.org/chapters?track=yes#top',
      id: 'user_sample_test',
    );
    expect(source.name, 'sample-reader.org');
    expect(source.url, 'https://sample-reader.org/chapters');
    expect(source.languages, ['fr', 'en']);
    expect(source.toCatalogSite().accepts(
        'https://sample-reader.org/chapters/15'), isTrue);
    final rule = SourceRecipeRegistry.defaults().forSite(source.id);
    expect(rule.mode, 'inspect');
    expect(rule.selectors, isNotEmpty);
  });

  test('private host, credentials, insecure URL and custom port are rejected', () {
    for (final invalid in [
      'http://reader.example.org',
      'https://127.0.0.1:9000',
      'https://10.0.0.1',
      'https://localhost',
      'https://private.local',
      'https://user:pass@example.org',
      'https://public.org:8443',
      'https://public.org.evil.example',
      'javascript:alert(1)',
    ]) {
      expect(() => normalizedSourceUri(invalid), throwsFormatException,
          reason: 'Should reject $invalid');
    }
  });

  test('user-source JSON survives roundtrip, keeps deactivated sources', () {
    final source = createUserSource(
      url: 'https://sample-reader.org/',
      name: 'Ma source', languages: ['fr'], id: 'user_sample_test',
    );
    final stored = UserSourceStore.decode(UserSourceStore.encode([
      source.withEnabled(false),
    ]));
    expect(stored.single.name, 'Ma source');
    expect(stored.single.enabled, false);
    expect(stored.single.languages, ['fr']);
    expect(() => UserSourceStore.decode('invalid'), throwsFormatException);
    expect(() => UserSourceStore.decode(UserSourceStore.encode([source, source])),
        throwsFormatException);
  });

  test('source metadata persists in its own file', () async {
    final dir = await Directory.systemTemp.createTemp('pazulu-sources-test');
    try {
      final store = UserSourceStore(File('${dir.path}/user-sources.json'));
      final source = createUserSource(
          url: 'https://sample-reader.org/', id: 'user_sample_test');
      await store.save([source]);
      expect((await store.load()).single.id, source.id);
      await store.save([source.withEnabled(false)]);
      expect((await store.load()).single.enabled, false);
      expect(await File('${dir.path}/user-sources.json.bak').exists(), true);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('one Cloudflare 525 never means permanently dead', () {
    final first = observeSourceHealth('a', null,
      SourceProbeResult(checkedAt: today, httpStatus: 525));
    expect(first.status, SourceHealthStatus.unstable);
    expect(first.failures, 1);
    final second = observeSourceHealth('a', first,
      SourceProbeResult(checkedAt: today.add(const Duration(hours: 12)), httpStatus: 525));
    expect(second.status, SourceHealthStatus.unstable);
    final third = observeSourceHealth('a', second,
      SourceProbeResult(checkedAt: today.add(const Duration(hours: 25)), httpStatus: 525));
    expect(third.status, SourceHealthStatus.suspectedOffline);
    expect(third.suspectedDead, true);
    final recovered = observeSourceHealth('a', third, SourceProbeResult(
      checkedAt: today.add(const Duration(hours: 27)),
      httpStatus: 200, isHtml: true,
    ));
    expect(recovered.status, SourceHealthStatus.reachable);
    expect(recovered.failures, 0);
    expect(recovered.firstFailureAt, isNull);
  });

  test('403/429 and redirected hosts mean blocked, not gone', () {
    for (final status in [403, 429]) {
      final health = observeSourceHealth('b', null,
          SourceProbeResult(checkedAt: today, httpStatus: status));
      expect(health.status, SourceHealthStatus.blocked);
      expect(health.failures, 0);
    }
    final moved = observeSourceHealth('b', null, SourceProbeResult(
      checkedAt: today, httpStatus: 301, isHtml: true,
      redirectHost: 'unknown-copy.example.net',
    ));
    expect(moved.status, SourceHealthStatus.blocked);
    expect(moved.note, contains('unknown-copy.example.net'));
  });

  test('health history survives JSON export/import', () {
    final current = observeSourceHealth('reader', null, SourceProbeResult(
      checkedAt: today, httpStatus: 503,
    ));
    final decoded = SourceHealthStore.decode(SourceHealthStore.encode([current]));
    expect(decoded['reader']!.failures, 1);
    expect(decoded['reader']!.httpStatus, 503);
  });

  test('editing a personal domain retains the source ID and enabled state', () {
    final initial = createUserSource(
      url: 'https://old-reader.org/',
      id: 'user_persistent_reader',
      languages: ['en'],
    ).withEnabled(false);
    final updated = initial.withDetails(
      url: 'https://new-reader.org/series/',
      name: 'Ma lecture',
      languages: ['fr', 'en'],
    );
    expect(updated.id, initial.id);
    expect(updated.enabled, isFalse);
    expect(updated.url, 'https://new-reader.org/series/');
    expect(updated.languages, ['fr', 'en']);
    expect(UserSourceStore.decode(UserSourceStore.encode([updated]))
        .single.id, initial.id);
    expect(() => initial.withDetails(
      url: 'http://localhost/', name: 'Mauvais', languages: ['en'],
    ), throwsFormatException);
  });
}
