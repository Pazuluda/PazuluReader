import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/achievements.dart';
import 'package:pazulu_reader/core/anime/anilist.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/coverage.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/library_store.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/planning.dart';
import 'package:pazulu_reader/core/release_detector.dart';
import 'package:pazulu_reader/core/schedule/schedule_service.dart';
import 'package:pazulu_reader/core/schedule/site_latest.dart';
import 'package:pazulu_reader/core/schedule/webtoon_daily.dart';
import 'package:pazulu_reader/core/schedule/weekly_schedule.dart';
import 'package:pazulu_reader/engine/identity/listing_guard.dart';

SourceChapter ch(String key, {String source = 'mangadex', String lang = 'en',
    DateTime? published}) =>
    SourceChapter(sourceId: source, chapterId: '$source-$key-$lang', key: ChapterKey.parse(key),
        lang: lang, group: 'g', pages: 3, publishedAt: published);

void main() {
  final now = DateTime(2026, 11, 7, 12);

  group('Nouveautés honnêtes', () {
    test('un chapitre publié il y a des années n\'est pas une « sortie »', () {
      final e = LibraryEntry(work: const WorkInfo(id: 'sl', title: 'Solo Leveling'));
      ReleaseDetector.observe(e, 'mangadex', [ch('200')], langs: ['en'], now: now);
      final fresh = ReleaseDetector.observe(e, 'mangadex', [
        ch('200'),
        ch('146', published: DateTime(2023, 1, 1)),
        ch('201', published: now.subtract(const Duration(hours: 2))),
      ], langs: ['en'], now: now);
      expect(fresh.map((c) => c.key.id), ['201']);
    });

    test('rattrapage massif sans date : aucune notification', () {
      final e = LibraryEntry(work: const WorkInfo(id: 'x', title: 'X'));
      ReleaseDetector.observe(e, 'mangadex', [ch('1')], langs: ['en'], now: now);
      final fresh = ReleaseDetector.observe(e, 'mangadex',
          [for (var i = 1; i <= 30; i++) ch('$i')], langs: ['en'], now: now);
      expect(fresh, isEmpty);
    });

    test('site web : chapitre 3861 d\'une autre série ignoré, dernier connu intact', () {
      final e = LibraryEntry(work: const WorkInfo(id: 'sl', title: 'Solo Leveling'));
      e.latestKnown['en'] = 200;
      final fresh = ReleaseDetector.observe(e, 'public_site', [
        ch('3861', source: 'public_site'), ch('201', source: 'public_site'),
      ], langs: ['en'], now: now);
      expect(fresh.map((c) => c.key.id), ['201']);
      expect(e.latestKnown['en'], 201);
    });

    test('nettoyage des anciennes notifications (rafale et numéros absurdes)', () {
      final e = LibraryEntry(work: const WorkInfo(id: 'sl', title: 'Solo Leveling'));
      e.observedChapters['mangadex|en'] = [for (var i = 1; i <= 200; i++) '$i'];
      e.latestKnown['en'] = 3862;
      final at = now.subtract(const Duration(minutes: 42));
      final updates = [
        for (final k in ['239', '240', '146', '126', '876', '877', '3861'])
          UpdateItem(workId: 'sl', title: 'SL', keyId: k, lang: 'en', group: 'g', foundAt: at),
        UpdateItem(workId: 'other', title: 'Dress-Up', keyId: '116', lang: 'en', group: 'g',
            foundAt: at, publishedAt: now.subtract(const Duration(days: 1))),
      ];
      UpdateHygiene.clean(updates, {'sl': e});
      expect(updates.map((u) => u.keyId), ['116']);
      expect(e.latestKnown['en'], 200);
    });

    test('date de sortie réelle utilisée par « Sorties confirmées »', () {
      final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'));
      final r = ReleasePlanner.recent([e], [
        UpdateItem(workId: 'w', title: 'W', keyId: '5', lang: 'en', group: 'g',
            foundAt: now, publishedAt: DateTime(2024, 1, 1)),
        UpdateItem(workId: 'w', title: 'W', keyId: '6', lang: 'en', group: 'g',
            foundAt: now, publishedAt: now.subtract(const Duration(hours: 3))),
      ], langs: const ['en'], now: now);
      expect(r.single.chapterLabel, 'Ch. 6');
      expect(r.single.date, now.subtract(const Duration(hours: 3)));
    });

    test('publishedAt survit à la sauvegarde', () {
      final u = UpdateItem(workId: 'w', title: 'W', keyId: '5', lang: 'en', group: 'g',
          foundAt: now, publishedAt: DateTime.utc(2026, 11, 1));
      expect(UpdateItem.fromJson(u.toJson()).publishedAt, DateTime.utc(2026, 11, 1));
    });
  });

  group('Chapitres manquants pour toutes les œuvres', () {
    test('trous dans la liste et dernier chapitre annoncé', () {
      final list = [for (var i = 1; i <= 198; i++) ch('$i'), ch('262'), ch('271')];
      expect(Coverage.holes(list), [(199, 261), (263, 270)]);
      expect(Coverage.incomplete([for (var i = 1; i <= 50; i++) ch('$i')], lastChapter: '330'), isTrue);
      expect(Coverage.incomplete([for (var i = 1; i <= 50; i++) ch('$i')]), isFalse);
    });

    test('liste complète 1…330 acceptée même si MangaDex s\'arrête à 50', () {
      final site = [for (var i = 1; i <= 330; i++) ch('$i', source: 'public_x')];
      final trusted = [for (var i = 1; i <= 50; i++) ch('$i')];
      expect(ListingGuard.dense(site), isTrue);
      expect(ListingGuard.rejectReason(site, trusted), isNull);
      final home = [ch('3862', source: 'public_x'), ch('877', source: 'public_x'),
        ch('240', source: 'public_x')];
      expect(ListingGuard.dense(home), isFalse);
    });

    test('fusion rapide : mêmes titres réunis, titres différents séparés', () {
      final works = [
        for (var i = 0; i < 3000; i++)
          WorkInfo(id: 's$i', title: 'Series ${i % 1500}',
              links: [SourceLink(sourceId: 'site${i ~/ 1500}', workId: '$i')]),
      ];
      final sw = Stopwatch()..start();
      final merged = mergeSearchResults(works);
      sw.stop();
      expect(merged, hasLength(1500));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('Heures écrites par les sites', () {
    test('relatives et absolues, FR et EN', () {
      (DateTime, bool)? p(String s) => ReleaseTimeParser.parse(s, now: now);
      expect(p('2 hours ago')!.$1, now.subtract(const Duration(hours: 2)));
      expect(p('2 hours ago')!.$2, isTrue);
      expect(p('il y a 35 minutes')!.$1, now.subtract(const Duration(minutes: 35)));
      expect(p('an hour ago')!.$1, now.subtract(const Duration(hours: 1)));
      expect(p('3 days ago')!.$2, isFalse);
      expect(p('November 6, 2026')!.$1, DateTime(2026, 11, 6));
      expect(p('6 novembre 2026')!.$1, DateTime(2026, 11, 6));
      expect(p('06/11/2026')!.$1, DateTime(2026, 11, 6));
      expect(p('Chapter 120'), isNull);
    });
  });

  group('Blocs « dernières mises à jour » des sites', () {
    final base = Uri.parse('https://site.example/');
    test('Madara', () {
      const html = '''
<div class="page-item-detail"><div class="item-thumb"><img src="/c.jpg"></div>
  <h3 class="h5"><a href="/manga/solo-leveling/">Solo Leveling</a></h3>
  <div class="chapter-item"><span class="chapter"><a href="/manga/solo-leveling/chapter-201/">Chapter 201</a></span>
    <span class="post-on"><a title="2 hours ago">x</a></span></div>
  <div class="chapter-item"><span class="chapter"><a href="/manga/solo-leveling/chapter-200/">Chapter 200</a></span>
    <span class="post-on">November 6, 2026</span></div>
</div>''';
      final r = SiteLatestParser.parse(html, base, now: now);
      expect(r, hasLength(2));
      expect(r.first.seriesTitle, 'Solo Leveling');
      expect(r.first.chapter.id, '201');
      expect(r.first.precise, isTrue);
      expect(r.first.seriesUrl, 'https://site.example/manga/solo-leveling/');
    });

    test('MangaThemesia', () {
      const html = '''
<div class="utao"><div class="uta"><div class="imgu"><a href="/manga/omniscient/"><img src="/o.jpg"></a></div>
<div class="luf"><a class="series" href="/manga/omniscient/"><h4>Omniscient Reader</h4></a>
<ul><li><a href="/omniscient-chapter-250/">Chapitre 250</a><span>il y a 3 heures</span></li></ul></div></div></div>''';
      final r = SiteLatestParser.parse(html, base, now: now);
      expect(r.single.seriesTitle, 'Omniscient Reader');
      expect(r.single.chapter.id, '250');
      expect(r.single.at, now.subtract(const Duration(hours: 3)));
    });
  });

  test('WEBTOON : séries rangées par jour', () {
    const html = '''
<div class="daily_section _list_MONDAY"><ul class="daily_card">
  <li><a href="https://www.webtoons.com/en/fantasy/tower-of-god/list?title_no=95"><p class="subj">Tower of God</p></a></li>
</ul></div>
<div class="daily_section _list_SATURDAY"><ul class="daily_card">
  <li><a href="https://www.webtoons.com/en/romance/lore/list?title_no=1320"><p class="subj">Lore Olympus</p></a></li>
</ul></div>''';
    final r = WebtoonDailyParser.parse(html, Uri.parse('https://www.webtoons.com/en/originals'));
    expect({for (final d in r) d.title: d.weekday}, {'Tower of God': 1, 'Lore Olympus': 6});
  });

  group('Planning de la semaine', () {
    test('lundi de la semaine', () {
      expect(WeeklyScheduleBuilder.weekStart(DateTime(2026, 11, 7, 18)), DateTime(2026, 11, 2));
    });

    test('rythme hebdomadaire à 17 h : projeté sur la semaine suivante', () {
      final history = <String, SeriesHistory>{};
      for (final d in [DateTime(2026, 10, 19, 17), DateTime(2026, 10, 26, 17),
        DateTime(2026, 11, 2, 17, 5)]) {
        WeeklyScheduleBuilder.record(history, title: 'Solo Leveling', lang: 'en', at: d,
            sourceId: 'mangadex', workId: 'abc', label: '${d.day}');
      }
      final next = WeeklyScheduleBuilder.project(history, DateTime(2026, 11, 9), now: now);
      expect(next, hasLength(1));
      expect(next.single.at.weekday, DateTime.monday);
      expect(next.single.at.hour, 17);
      expect(next.single.timeKnown, isTrue);
      expect(next.single.state, SlotState.estimated);
      expect(next.single.work!.id, 'mangadex:abc');
    });

    test('fusion : une ligne par série et par jour, « Sorti » prioritaire', () {
      final day = DateTime(2026, 11, 2);
      final merged = WeeklyScheduleBuilder.merge([
        ScheduleSlot(kind: SlotKind.comic, title: 'Solo Leveling', at: day, timeKnown: false,
            lang: 'en', label: 'Ch. 201', state: SlotState.estimated, providers: {'Rythme observé'}),
        ScheduleSlot(kind: SlotKind.comic, title: 'Solo Leveling', at: day.add(const Duration(hours: 17)),
            timeKnown: true, lang: 'en', label: 'Ch. 201', state: SlotState.released,
            providers: {'MangaDex'}),
        ScheduleSlot(kind: SlotKind.comic, title: 'Solo Leveling', at: day, timeKnown: false,
            lang: 'fr', label: 'Ch. 199', state: SlotState.released, providers: {'Sushi'}),
      ]);
      expect(merged, hasLength(2));
      final en = merged.firstWhere((s) => s.lang == 'en');
      expect(en.state, SlotState.released);
      expect(en.timeKnown, isTrue);
      expect(en.providers, {'MangaDex', 'Rythme observé'});
    });

    test('« Ma liste » : séries suivies seulement', () {
      final mine = [LibraryEntry(work: const WorkInfo(id: 'x', title: 'Solo Leveling',
          type: ContentType.manhwa))];
      ScheduleSlot slot(String t) => ScheduleSlot(kind: SlotKind.comic, title: t, at: now,
          timeKnown: true, lang: 'en', label: '', state: SlotState.released, providers: {'a'});
      expect(WeeklyScheduleBuilder.followed(slot('Solo Leveling'), mine), isTrue);
      expect(WeeklyScheduleBuilder.followed(slot('Tower of God'), mine), isFalse);
    });

    test('le planning de la semaine survit au redémarrage', () {
      final s = ScheduleSlot(kind: SlotKind.anime, title: 'Frieren', at: DateTime.utc(2026, 11, 7, 14),
          timeKnown: true, lang: 'ja', label: 'Épisode 5', state: SlotState.scheduled,
          providers: {'AniList'},
          streams: const [StreamingLink(site: 'Crunchyroll', url: 'https://crunchyroll.com/x')],
          work: const WorkInfo(id: 'anilist:1', title: 'Frieren', type: ContentType.anime));
      final back = ScheduleService.slotFromJson(ScheduleService.slotToJson(s))!;
      expect(back.kind, SlotKind.anime);
      expect(back.at.isAtSameMomentAs(s.at), isTrue);
      expect(back.streams.single.site, 'Crunchyroll');
      expect(AniListClient.idOf(back.work!), 1);
    });
  });

  test('catalogue AniList : pays → manga / manhwa / manhua', () {
    final w = AniListClient.comicFromJson({
      'id': 7, 'title': {'english': 'Catastrophic Necromancer'}, 'countryOfOrigin': 'KR',
      'status': 'RELEASING', 'chapters': 330, 'averageScore': 78, 'genres': ['Action'],
    })!;
    expect(w.type, ContentType.manhwa);
    expect(w.lastChapter, '330');
    expect(w.tags, contains('Action'));
    expect(w.publicationStatus, 'En cours');
  });

  group('Niveaux et succès', () {
    test('courbe de niveaux', () {
      expect(Level.of(0).number, 1);
      expect(Level.of(50).number, 2);
      expect(Level.of(4050).number, 10);
      expect(Level.of(120).progress, inInclusiveRange(0, 1));
    });

    test('série de jours, année et succès', () {
      final log = ActivityLog();
      for (var i = 0; i < 7; i++) {
        log.addChapters(2, at: now.subtract(Duration(days: i)));
      }
      final e = LibraryEntry(work: const WorkInfo(id: 'a', title: 'A', tags: ['Action']));
      e.progress.readKeys.addAll([for (var i = 1; i <= 120; i++) '$i']);
      final s = ReaderStats.compute([e], log, now: now);
      expect(s.chapters, 120);
      expect(s.currentStreak, 7);
      expect(s.bestStreak, 7);
      expect(s.yearChapters, 14);
      expect(s.topGenres.first.key, 'Action');
      final fresh = Achievements.unlock(s, log, now: now);
      expect(fresh.map((a) => a.id), containsAll(['first_chapter', 'ch_100', 'streak_7']));
      expect(Achievements.unlock(s, log, now: now), isEmpty);
    });

    test('journal sauvegardé avec la bibliothèque', () {
      final data = LibraryData();
      data.activity.addEpisodes(2, at: now);
      data.activity.unlocked['ep_1'] = now.toIso8601String();
      final back = LibraryData.fromJson(data.toJson());
      expect(back.activity.days.values.single.episodes, 2);
      expect(back.activity.unlocked, contains('ep_1'));
    });
  });
}
