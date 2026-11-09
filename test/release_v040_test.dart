import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/library_store.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/release_detector.dart';
import 'package:pazulu_reader/core/source_catalog.dart';

SourceChapter release(String key, String lang, {
  String source = 'mangadex',
  DateTime? published,
  String group = 'G',
}) => SourceChapter(
      sourceId: source,
      chapterId: '$key-$lang-$group',
      key: ChapterKey.parse(key),
      lang: lang,
      group: group,
      publishedAt: published,
      pages: 2,
    );

LibraryEntry tracked() => LibraryEntry(
      work: const WorkInfo(id: 'mangadex:test', title: 'Exemple'),
    );

void main() {
  group('Détection v0.4.0', () {
    test('premier contrôle établit un état sans alerte rétrospective', () {
      final e = tracked();
      final initial = [release('51', 'en'), release('49', 'fr')];
      expect(ReleaseDetector.observe(e, 'mangadex', initial,
          langs: ['en', 'fr']), isEmpty);
      expect(e.observedChapters['mangadex|en'], contains('51'));
      expect(e.observedChapters['mangadex|fr'], contains('49'));
    });

    test('nouveau français détecté même si son numéro est inférieur au max EN', () {
      final e = tracked();
      ReleaseDetector.observe(e, 'mangadex', [
        release('100', 'en'), release('45', 'fr'),
      ], langs: ['en', 'fr']);
      final fresh = ReleaseDetector.observe(e, 'mangadex', [
        release('100', 'en'), release('45', 'fr'), release('46', 'fr'),
      ], langs: ['en', 'fr']);
      expect(fresh.map((c) => '${c.lang}:${c.key.id}'), ['fr:46']);
    });

    test('chapitre FR ajouté avec un numéro ancien est quand même détecté', () {
      final e = tracked();
      ReleaseDetector.observe(e, 'mangadex', [
        release('60', 'fr'), release('58', 'fr'),
      ], langs: ['fr']);
      expect(ReleaseDetector.observe(e, 'mangadex', [
        release('60', 'fr'), release('59', 'fr'), release('58', 'fr'),
      ], langs: ['fr']).map((c) => c.key.id), ['59']);
    });

    test('pas de doublons si la même traduction a deux groupes', () {
      final e = tracked();
      ReleaseDetector.observe(e, 'mangadex', [release('1', 'en')], langs: ['en']);
      final r = ReleaseDetector.observe(e, 'mangadex', [
        release('2', 'en', group: 'A'),
        release('2', 'en', group: 'B'),
      ], langs: ['en']);
      expect(r.length, 1);
      expect(ReleaseDetector.observe(e, 'mangadex', [release('2', 'en')],
          langs: ['en']), isEmpty);
    });

    test('ne signale pas un chapitre prévu dans le futur', () {
      final e = tracked();
      final now = DateTime.utc(2026, 11, 5, 18);
      ReleaseDetector.observe(e, 'mangadex', [], langs: ['en'], now: now);
      final r = ReleaseDetector.observe(e, 'mangadex', [
        release('5', 'en', published: now.add(const Duration(days: 1))),
      ], langs: ['en'], now: now);
      expect(r, isEmpty);
      expect(e.observedChapters['mangadex|en'], isEmpty);
    });

    test('ancien latestKnown migre sans notifier toute la série', () {
      final e = tracked()..latestKnown['en'] = 20;
      final r = ReleaseDetector.observe(e, 'mangadex', [
        release('18', 'en'), release('20', 'en'), release('21', 'en'),
      ], langs: ['en']);
      expect(r.map((c) => c.key.id), ['21']);
    });

    test('une œuvre manuelle conserve ses liens dans la bibliothèque', () {
      final e = LibraryEntry(
        work: const WorkInfo(id: 'manual:42', title: 'Autre série',
            type: ContentType.manhwa, languages: ['fr', 'en']),
        watch: false,
      );
      e.savedSiteLinks.add(const SavedSiteLink(
        siteId: 'webtoon_fr',
        url: 'https://www.webtoons.com/fr/fantasy/example/list?title_no=42',
        lang: 'fr',
      ));
      final library = LibraryData()..entries[e.work.id] = e;
      final recovered = LibraryData.fromJson(library.toJson());
      expect(recovered.entries[e.work.id]!.work.type, ContentType.manhwa);
      expect(recovered.entries[e.work.id]!.watch, isFalse);
      expect(recovered.entries[e.work.id]!.savedSiteLinks.single.siteId,
          'webtoon_fr');
    });

    test('snapshot présent dans une sauvegarde et fusionné sans perte', () {
      final old = LibraryData();
      final newer = LibraryData();
      final a = tracked();
      a.observedChapters['mangadex|fr'] = ['5', '6'];
      a.savedSiteLinks.add(const SavedSiteLink(
        siteId: 'asurascans', url: 'https://asurascans.com/series/test', lang: 'en'));
      old.entries[a.work.id] = a;
      final b = tracked();
      b.observedChapters['mangadex|fr'] = ['6', '7'];
      newer.entries[b.work.id] = b;
      LibraryStore.merge(old, newer);
      final merged = old.entries[a.work.id]!;
      expect(merged.observedChapters['mangadex|fr'], containsAll(['5', '6', '7']));
      expect(merged.savedSiteLinks.length, 1);
      final decoded = LibraryData.fromJson(old.toJson());
      expect(decoded.entries[a.work.id]!.savedSiteLinks.length, 1);
    });
  });

  group('Catalogue actif : 13 sources et 2 archivees', () {
    test('garde les anciennes adresses en lecture seule de compatibilite', () {
      expect(catalogSites.length, 13);
      expect(archivedCatalogSites.length, 2);
      expect([...catalogSites, ...archivedCatalogSites].map((s) => s.id).toSet().length, 15);
      expect(catalogSiteById('manhwaclan'), isNotNull);
      expect(catalogSites.any((s) => s.id == 'manhwaclan'), isFalse);
      expect(catalogSites.where((s) => s.hasReaderConnector).map((s) => s.id),
          ['mangadex']);
    });

    test('n’enregistre pas un lien hors du site ou non HTTPS', () {
      final s = catalogSiteById('asurascans')!;
      expect(s.accepts('https://asurascans.com/series/abc'), isTrue);
      expect(s.accepts('http://asurascans.com/series/abc'), isFalse);
      expect(s.accepts('https://asurascans.com.evil.example/a'), isFalse);
      expect(s.accepts('javascript:alert(1)'), isFalse);
      expect(s.accepts('https://user:pass@asurascans.com/a'), isFalse);
    });
  });
}
