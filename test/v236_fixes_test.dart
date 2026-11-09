import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/release_detector.dart';
import 'package:pazulu_reader/core/sources/sushiscan.dart';

SourceChapter ch(String key, String source, {DateTime? published, String lang = 'en'}) =>
    SourceChapter(sourceId: source, chapterId: '$source-$key', key: ChapterKey.parse(key),
        lang: lang, group: source, pages: 3, publishedAt: published);

void main() {
  final now = DateTime(2026, 11, 8, 18);

  test('un chapitre déjà listé par une autre source n\'est pas une sortie', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'd', title: 'Darling'));
    e.observedChapters['mangadex|en'] = [for (var i = 1; i <= 116; i++) '$i'];
    ReleaseDetector.observe(e, 'site_a', [ch('115', 'site_a')], langs: ['en'], now: now);
    final fresh = ReleaseDetector.observe(e, 'site_a',
        [ch('115', 'site_a'), ch('116', 'site_a')], langs: ['en'], now: now);
    expect(fresh, isEmpty);
  });

  test('série terminée : pas de « nouveau » chapitre sans date', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'd', title: 'Darling',
        publicationStatus: 'Terminé'));
    ReleaseDetector.observe(e, 'site_a', [ch('115', 'site_a')], langs: ['en'], now: now);
    final fresh = ReleaseDetector.observe(e, 'site_a',
        [ch('115', 'site_a'), ch('116', 'site_a')], langs: ['en'], now: now);
    expect(fresh, isEmpty);
  });

  test('une vraie sortie (seule source, en cours) reste annoncée', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'n', title: 'Necro',
        publicationStatus: 'En cours'));
    ReleaseDetector.observe(e, 'site_a', [ch('318', 'site_a')], langs: ['en'], now: now);
    final fresh = ReleaseDetector.observe(e, 'site_a',
        [ch('318', 'site_a'), ch('319', 'site_a')], langs: ['en'], now: now);
    expect(fresh.map((c) => c.key.id), ['319']);
  });

  test('ancienne notification d\'une série terminée retirée au démarrage', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'd', title: 'Darling',
        publicationStatus: 'Terminé'));
    final updates = [
      UpdateItem(workId: 'd', title: 'Darling', keyId: '116', lang: 'en', group: 'x',
          foundAt: now.subtract(const Duration(days: 1))),
    ];
    UpdateHygiene.clean(updates, {'d': e});
    expect(updates, isEmpty);
  });

  test('SushiScan : date de sortie lue sur la liste (MangaThemesia)', () {
    const series = 'https://sushiscan.net/catalogue/overgeared/';
    const html = '''
<html><head><title>Overgeared</title></head><body><h1>Overgeared</h1>
<div class="eplister"><ul>
<li data-num="272"><div class="chbox"><div class="eph-num">
<a href="https://sushiscan.net/overgeared-chapitre-272/">
<span class="chapternum">Chapitre 272</span>
<span class="chapterdate">janvier 16, 2026</span></a></div></div></li>
<li data-num="271"><div class="chbox"><div class="eph-num">
<a href="https://sushiscan.net/overgeared-chapitre-271/">
<span class="chapternum">Chapitre 271</span>
<span class="chapterdate">12 janvier 2026</span></a></div></div></li>
</ul></div></body></html>''';
    final list = SushiScanSource.parseChapters(html, series);
    final byId = {for (final c in list) c.key.id: c};
    expect(byId['272']?.publishedAt, DateTime(2026, 1, 16));
    expect(byId['271']?.publishedAt, DateTime(2026, 1, 12));
  });
}
