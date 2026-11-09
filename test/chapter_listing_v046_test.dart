import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_listing.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/release_detector.dart';
import 'package:pazulu_reader/core/source_catalog.dart';

const site = CatalogSite('test', 'Demo Reader', 'https://reader.example.org/',
    ['en', 'fr'], SiteIntegration.website);

void main() {
  group('Listing HTML public V0.4.6', () {
    test('liste dedupliquee, liens internes, fractions et pages sans autorisation', () {
      final result = ChapterListingParser.parseListing('''
        <html><head><title>Demo Reader</title></head><body>
        <a href="/series/alpha/chapter-12">Chapter 12</a>
        <a href="/series/alpha/chapter-12?version=2">Chapter 12</a>
        <a href="/series/alpha/chapter-12.5">Chapter 12.5</a>
        <a href="/series/alpha/chapter-13" class="locked">Chapter 13</a>
        <a href="/series/alpha">Read more</a>
        <a href="https://other.example.org/chapter-999">Chapter 999</a>
        <a href="javascript:alert(1)">Chapter 500</a>
        </body></html>
      ''', pageUrl: 'https://reader.example.org/series/alpha', site: site);
      expect(result.map((e) => e.key.id).toList(), ['12', '12.5']);
      expect(result.every((e) => e.url.startsWith('https://reader.example.org/')), true);
    });

    test('accepte le numero dans le libelle ou le chemin', () {
      final result = ChapterListingParser.parseListing('''
        <a href="/series/abc/episode-32.html">Ouvrir</a>
        <a href="/series/abc/slug-33">Chapitre : 33</a>
      ''', pageUrl: 'https://reader.example.org/series/abc', site: site);
      expect(result.map((e) => e.key.id), containsAll(['32', '33']));
    });

    test('aucune annonce si la page est vide, bloquee ou purement JS', () {
      for (final html in [
        '',
        '<title>Just a moment...</title>checking your browser',
        '<html><div id="root"></div><script>loadChapters()</script></html>',
      ]) {
        expect(() => ChapterListingParser.parseListing(html,
          pageUrl: 'https://reader.example.org/series/a', site: site),
          throwsA(isA<ListingUnavailable>()));
      }
    });

    test('interdit les pages en dehors de la source', () {
      expect(() => ChapterListingParser.parseListing(
        '<a href="/chapter-3">Chapter 3</a>',
        pageUrl: 'https://other.example.org/series/a', site: site,
      ), throwsA(isA<ListingUnavailable>()));
    });

    test('les chapitres constates ne sont pas des fichiers images', () {
      final links = ChapterListingParser.parseListing(
        '<a href="/series/a/chapter-7">Chapter 7</a>',
        pageUrl: 'https://reader.example.org/series/a', site: site,
      );
      final chapters = ChapterListingParser.asChapters(links,
        bucketId: 'listing:test:link', language: 'en', label: 'Demo Reader');
      expect(chapters.single.pages, 0);
      expect(chapters.single.externalUrl, links.single.url);
      expect(chapters.single.isExternal, isTrue);
    });
  });

  group('Notifications multisources V0.4.6', () {
    test('premiere observation externe silencieuse meme apres MangaDex', () {
      final entry = LibraryEntry(work: const WorkInfo(id: 'manual:1', title: 'Demo'));
      entry.latestKnown['en'] = 9;
      List<SourceChapter> chapters(String key) => [
        SourceChapter(sourceId: 'listing:demo:abc', chapterId: 'demo:$key',
          key: ChapterKey.parse(key), lang: 'en', group: 'Demo'),
      ];
      expect(ReleaseDetector.observe(entry, 'listing:demo:abc', chapters('15'),
        langs: ['en'], firstObservationIsBaseline: true), isEmpty);
      final fresh = ReleaseDetector.observe(entry, 'listing:demo:abc',
        [...chapters('15'), ...chapters('16')],
        langs: ['en'], firstObservationIsBaseline: true);
      expect(fresh.map((c) => c.key.id), ['16']);
      expect(ReleaseDetector.observe(entry, 'listing:demo:abc', chapters('16'),
        langs: ['en'], firstObservationIsBaseline: true), isEmpty);
    });

    test('la variante FR tardive et la source sont conservees en sauvegarde', () {
      final entry = LibraryEntry(work: const WorkInfo(id: 'manual:2', title: 'Demo'));
      SourceChapter link(String key) => SourceChapter(
        sourceId: 'listing:demo:other', chapterId: key,
        key: ChapterKey.parse(key), lang: 'fr', group: 'Demo');
      ReleaseDetector.observe(entry, 'listing:demo:other', [link('25'), link('29')],
        langs: ['fr'], firstObservationIsBaseline: true);
      expect(ReleaseDetector.observe(entry, 'listing:demo:other',
        [link('25'), link('28'), link('29')], langs: ['fr'],
        firstObservationIsBaseline: true).map((c) => c.key.id), ['28']);
      final roundtrip = LibraryEntry.fromJson(entry.toJson());
      expect(roundtrip.observedChapters['listing:demo:other|fr'],
          containsAll(['25', '28', '29']));
    });

    test('notification avec URL explicite : compatibilite anciennes sauvegardes', () {
      final updated = UpdateItem(
        workId: 'manual:3', title: 'Demo', keyId: '20', lang: 'fr',
        group: 'Reader', foundAt: DateTime.utc(2026, 11, 5),
        siteId: 'test', chapterUrl: 'https://reader.example.org/chapter-20',
      );
      final decoded = UpdateItem.fromJson(updated.toJson());
      expect(decoded.chapterUrl, updated.chapterUrl);
      expect(decoded.siteId, 'test');
      final legacy = Map<String, dynamic>.of(updated.toJson())
        ..remove('siteId')..remove('chapterUrl');
      expect(UpdateItem.fromJson(legacy).chapterUrl, isNull);
    });
  });
}
