import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/planning.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';

import 'engine_v2_support.dart';

LibraryEntry entry(String title, {Map<String, List<DateTime>> dates = const {},
    Map<String, double> latest = const {}, List<int> days = const []}) => LibraryEntry(
      work: WorkInfo(id: title, title: title),
      releaseDates: {
        for (final e in dates.entries)
          e.key: ReleasePlanner.addDates(const [], e.value),
      },
      latestKnown: Map.of(latest),
      readingDays: List.of(days),
    );

void main() {
  final now = DateTime(2026, 11, 6, 12);
  List<DateTime> weekly(int count, DateTime last) =>
      [for (var i = 0; i < count; i++) last.subtract(Duration(days: 7 * i))];

  group('Planning des sorties', () {
    test('une seule sortie par jour, ordre récent d\'abord, borné', () {
      final d = DateTime(2026, 11, 1, 10);
      final dates = ReleasePlanner.addDates(const [], [d, d.add(const Duration(hours: 2)),
        d.subtract(const Duration(days: 7))]);
      expect(dates, hasLength(2));
      expect(DateTime.parse(dates.first).isAfter(DateTime.parse(dates.last)), isTrue);
      expect(ReleasePlanner.addDates(const [], weekly(40, d)), hasLength(16));
    });

    test('rythme hebdomadaire => prochaine sortie 7 jours après la dernière', () {
      final e = entry('Weekly', dates: {'en': weekly(6, DateTime(2026, 11, 3, 15))},
          latest: {'en': 120});
      final f = ReleasePlanner.forecast([e], langs: const ['en', 'fr'], now: now);
      expect(f, hasLength(1));
      expect(f.single.lang, 'en');
      expect(f.single.interval!.inDays, 7);
      expect(f.single.date.day, 10);
      expect(f.single.chapterLabel, 'Ch. 121');
      expect(f.single.confirmed, isFalse);
      expect(f.single.isLate, isFalse);
    });

    test('moins de trois sorties : aucune estimation inventée', () {
      final e = entry('New', dates: {'fr': weekly(2, DateTime(2026, 11, 3))});
      expect(ReleasePlanner.forecast([e], langs: const ['fr'], now: now), isEmpty);
    });

    test('estimation dépassée : « en retard », puis considérée en pause', () {
      final lateEntry = entry('Late', dates: {'en': weekly(5, DateTime(2026, 10, 27))});
      final f = ReleasePlanner.forecast([lateEntry], langs: const ['en'], now: now);
      expect(f.single.isLate, isTrue);
      final paused = entry('Paused', dates: {'en': weekly(5, DateTime(2026, 10, 1))});
      final p = ReleasePlanner.forecast([paused], langs: const ['en'], now: now);
      expect(p.single.state, ReleaseState.hiatus);
      final pause = entry('Pause', dates: {'en': weekly(5, DateTime(2026, 10, 15))});
      expect(ReleasePlanner.forecast([pause], langs: const ['en'], now: now).single.state,
          ReleaseState.pauseLikely);
    });

    test('langues séparées : EN hebdomadaire, FR sans historique', () {
      final e = entry('Both', dates: {'en': weekly(4, DateTime(2026, 11, 5))});
      expect(ReleasePlanner.forecast([e], langs: const ['fr'], now: now), isEmpty);
      expect(ReleasePlanner.forecast([e], langs: const ['en'], now: now), hasLength(1));
    });

    test('sorties confirmées récentes filtrées par langue et par date', () {
      final e = entry('Solo');
      final updates = [
        UpdateItem(workId: 'Solo', title: 'Solo', keyId: '200', lang: 'fr', group: 'g',
            foundAt: now.subtract(const Duration(days: 1))),
        UpdateItem(workId: 'Solo', title: 'Solo', keyId: '199', lang: 'en', group: 'g',
            foundAt: now.subtract(const Duration(days: 30))),
      ];
      final r = ReleasePlanner.recent([e], updates, langs: const ['en', 'fr'], now: now);
      expect(r, hasLength(1));
      expect(r.single.chapterLabel, ChapterKey.parse('200').label);
    });
  });

  group('Mes lectures', () {
    test('œuvres prévues pour un jour donné et chapitres non lus', () {
      final a = entry('A', days: [1, 3], latest: {'en': 50});
      final b = entry('B', days: [3]);
      a.progress.lastKey = '45';
      expect(ReleasePlanner.plannedOn([a, b], 3).map((e) => e.work.title), ['A', 'B']);
      expect(ReleasePlanner.plannedOn([a, b], 1).map((e) => e.work.title), ['A']);
      expect(ReleasePlanner.unreadEstimate(a, const ['en', 'fr']), 5);
    });

    test('le planning survit à la sauvegarde JSON', () {
      final a = entry('A', days: [2, 6], dates: {'en': weekly(3, now)});
      a.readingGoal = 3;
      final back = LibraryEntry.fromJson(a.toJson());
      expect(back.readingDays, [2, 6]);
      expect(back.readingGoal, 3);
      expect(back.releaseDates['en'], hasLength(3));
    });
  });

  group('Connecteur universel des sites web', () {
    const site = CatalogSite('directory_042', 'ManhuaUS', 'https://manhuaus.com/', ['en'],
        SiteIntegration.website);

    test('liste de chapitres Madara : lecteurs natifs, plus des liens externes', () async {
      final source = PublicCatalogSource(site,
          fetchHtml: (_) async => fixture('madara_series.html'));
      final chapters = await source.listChapters(
          'https://manhuaus.com/manga/martial-peak/', langs: const ['en']);
      expect(chapters.every((c) => !c.isExternal), isTrue);
      expect(chapters.map((c) => c.key.id).toSet(),
          containsAll(['116', '115.2', '115.1', 'extra-1', 'volume-12-bonus']));
      expect(chapters.any((c) => c.chapterId.contains('evil.example')), isFalse);
    });

    test('pages lazy-load récupérées, validées ensuite par le moteur', () async {
      final source = PublicCatalogSource(site,
          fetchHtml: (_) async => fixture('madara_lazy_chapter.html'));
      final fetch = await source.fetchPages(SourceChapter(sourceId: source.id,
          chapterId: 'https://manhuaus.com/manga/martial-peak/chapter-12/',
          key: ChapterKey.parse('12'), lang: 'en', group: 'ManhuaUS'));
      expect(fetch.pages, hasLength(5));
      expect(fetch.needsBrowser, isFalse);
      expect(fetch.imageHeaders['Referer'], contains('chapter-12'));
    });

    test('lecteur ts_reader (MangaThemesia) reconnu automatiquement', () async {
      const ts = CatalogSite('directory_100', 'Sushi', 'https://sushiscan.fr/', ['fr'],
          SiteIntegration.website);
      final source = PublicCatalogSource(ts,
          fetchHtml: (_) async => fixture('sushiscan_ts_reader_14.html'));
      final fetch = await source.fetchPages(SourceChapter(sourceId: source.id,
          chapterId: 'https://sushiscan.fr/solo-leveling-chapitre-198/',
          key: ChapterKey.parse('198'), lang: 'fr', group: 'Sushi'));
      expect(fetch.pages, hasLength(14));
      expect(fetch.announcedTotal, 14);
    });

    test('page d\'accueil : fiches seulement (pas de chapitre, pas d\'autre domaine)', () async {
      final source = PublicCatalogSource(site,
          fetchHtml: (_) async => fixture('madara_search.html'));
      final works = await source.browseLatest();
      expect(works.map((w) => w.title), ['Martial Peak']);
      expect(works.single.type, ContentType.other);
    });
  });
}
