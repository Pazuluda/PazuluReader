import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/anime/anilist.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/planning.dart';
import 'package:pazulu_reader/ui/format.dart';

int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

Map<String, Object?> media({
  int id = 1,
  String status = 'RELEASING',
  Map<String, Object?>? next,
  List<Object?> relations = const [],
  List<Object?> links = const [],
}) => {
      'id': id,
      'title': {'romaji': 'Ore dake Level Up na Ken', 'english': 'Solo Leveling', 'native': '俺だけレベルアップな件'},
      'synonyms': ['Na Honjaman Level Up'],
      'description': 'Hunter <i>Sung Jinwoo</i>.<br>Season 2.',
      'coverImage': {'large': 'https://img.anili.st/cover.jpg'},
      'bannerImage': 'https://img.anili.st/banner.jpg',
      'status': status,
      'episodes': 13,
      'format': 'TV',
      'season': 'WINTER',
      'seasonYear': 2025,
      'averageScore': 84,
      'genres': ['Action', 'Fantasy'],
      'studios': {'nodes': [{'name': 'A-1 Pictures'}]},
      'nextAiringEpisode': next,
      'externalLinks': links,
      'relations': {'edges': relations},
      'siteUrl': 'https://anilist.co/anime/1',
    };

void main() {
  final now = DateTime(2026, 11, 6, 12);

  group('AniList : lecture des données', () {
    test('titres, épisode suivant, studios et genres', () {
      final at = DateTime(2026, 11, 8, 17, 30);
      final info = AnimeInfo.fromJson(media(next: {'episode': 6, 'airingAt': secs(at)}))!;
      expect(info.title, 'Solo Leveling');
      expect(info.altTitles, containsAll(['Ore dake Level Up na Ken', 'Na Honjaman Level Up']));
      expect(info.description, isNot(contains('<')));
      expect(info.nextAiring!.episode, 6);
      expect(info.nextAiring!.airingAt, at);
      expect(info.airedEpisodes, 5);
      expect(info.studios, ['A-1 Pictures']);
      expect(info.seasonLabel, 'Hiver 2025');
      final work = info.toWork();
      expect(work.type, ContentType.anime);
      expect(AniListClient.idOf(work), 1);
    });

    test('seuls les liens de streaming officiels en https sont gardés', () {
      final info = AnimeInfo.fromJson(media(links: [
        {'site': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/x', 'type': 'STREAMING'},
        {'site': 'Twitter', 'url': 'https://twitter.com/x', 'type': 'SOCIAL'},
        {'site': 'Pirate', 'url': 'http://insecure.example/x', 'type': 'STREAMING'},
        {'site': 'Netflix', 'url': 'javascript:alert(1)', 'type': 'STREAMING'},
      ]))!;
      expect(info.streaming.map((s) => s.site), ['Crunchyroll']);
    });

    test('données invalides : rien n\'est inventé', () {
      expect(AnimeInfo.fromJson(null), isNull);
      expect(AnimeInfo.fromJson({'title': 'x'}), isNull);
    });
  });

  group('Planning des animés', () {
    LibraryEntry entryFor(AnimeInfo info) => LibraryEntry(work: info.toWork());

    test('horaires exacts, et reprise après une pause dans la grille', () {
      final info = AnimeInfo.fromJson(media())!;
      final e = entryFor(info);
      final airings = [
        AnimeAiring(mediaId: 1, episode: 5, airingAt: now.subtract(const Duration(days: 7))),
        AnimeAiring(mediaId: 1, episode: 6, airingAt: now.add(const Duration(days: 1, hours: 5))),
        AnimeAiring(mediaId: 1, episode: 7, airingAt: now.add(const Duration(days: 22, hours: 5))),
      ];
      final r = ReleasePlanner.animePlanning([e], {1: info}, airings, now: now);
      expect(r, hasLength(2));
      expect(r.first.state, ReleaseState.announced);
      expect(r.first.timeKnown, isTrue);
      expect(r.first.chapterLabel, 'Épisode 6');
      expect(r.last.state, ReleaseState.resumed);
      expect(r.last.note, contains('pause'));
    });

    test('hiatus annoncé et nouvelle saison sans date', () {
      final info = AnimeInfo.fromJson(media(status: 'HIATUS', relations: [
        {'relationType': 'SEQUEL', 'node': {'id': 2, 'type': 'ANIME', 'status': 'NOT_YET_RELEASED',
          'title': {'english': 'Solo Leveling Season 3'}}},
        {'relationType': 'SOURCE', 'node': {'id': 3, 'type': 'MANGA', 'status': 'FINISHED',
          'title': {'english': 'Solo Leveling'}}},
      ]))!;
      final r = ReleasePlanner.animePlanning([entryFor(info)], {1: info}, const [], now: now);
      expect(r.map((x) => x.state), containsAll([ReleaseState.hiatus, ReleaseState.newSeason]));
      final season = r.firstWhere((x) => x.state == ReleaseState.newSeason);
      expect(season.dateKnown, isFalse);
      expect(season.chapterLabel, 'Solo Leveling Season 3');
    });

    test('les animés ne passent jamais dans l\'estimation des chapitres', () {
      final info = AnimeInfo.fromJson(media())!;
      final e = entryFor(info);
      e.releaseDates['en'] = ReleasePlanner.addDates(const [],
          [for (var i = 0; i < 5; i++) now.subtract(Duration(days: 7 * i))]);
      expect(ReleasePlanner.forecast([e], langs: const ['en'], now: now), isEmpty);
    });
  });

  group('Heure habituelle des sorties', () {
    test('sorties régulières vers 15 h : l\'heure est prévue', () {
      final dates = [
        for (var i = 0; i < 5; i++) DateTime(2026, 10, 1 + 7 * i, 15, i * 10),
      ];
      final t = ReleasePlanner.typicalTime(dates)!;
      expect(t.inHours, 15);
      final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'),
          releaseDates: {'en': ReleasePlanner.addDates(const [], dates)});
      final f = ReleasePlanner.forecast([e], langs: const ['en'], now: DateTime(2026, 11, 1));
      expect(f.single.timeKnown, isTrue);
      expect(f.single.date.hour, 15);
    });

    test('heures dispersées ou minuit seul : pas d\'heure inventée', () {
      expect(ReleasePlanner.typicalTime([
        DateTime(2026, 10, 1, 2), DateTime(2026, 10, 8, 11), DateTime(2026, 10, 15, 20),
        DateTime(2026, 10, 22, 6),
      ]), isNull);
      expect(ReleasePlanner.typicalTime([
        DateTime(2026, 10, 1), DateTime(2026, 10, 8), DateTime(2026, 10, 15),
      ]), isNull);
    });
  });

  group('Confirmation du titre sur la page du site', () {
    const work = WorkInfo(id: 'sl', title: 'Solo Leveling', altTitles: ['Na Honjaman Level Up']);
    test('le titre de la fiche du site doit correspondre', () {
      expect(titleConfirms(work, 'Solo Leveling - Read Manhwa Online Free'), isTrue);
      expect(titleConfirms(work, 'Na Honjaman Level Up | Manhwatop'), isTrue);
      expect(titleConfirms(work, 'Solo Leveling: Ragnarok - Manhwatop'), isFalse);
      expect(titleConfirms(work, 'The Max Level Hero Has Returned! - Manhwatop'), isFalse);
    });
  });

  group('Mémoire des chapitres (affichage instantané)', () {
    test('un chapitre survit à l\'aller-retour JSON', () {
      final c = SourceChapter(sourceId: 'mangadex', chapterId: 'abc',
          key: ChapterKey.parse('115.2'), lang: 'fr', group: 'Team', title: 'Partie 2',
          pages: 18, publishedAt: DateTime.utc(2026, 11, 1), volume: '12');
      final back = SourceChapter.fromJson(c.toJson())!;
      expect(back.key.id, '115.2');
      expect(back.lang, 'fr');
      expect(back.title, 'Partie 2');
      expect(back.pages, 18);
      expect(back.volume, '12');
      expect(back.publishedAt, DateTime.utc(2026, 11, 1));
      expect(SourceChapter.fromJson({'s': 'x'}), isNull);
    });
  });

  group('Compte à rebours', () {
    final base = DateTime(2026, 11, 6, 12);
    test('formats lisibles', () {
      expect(countdown(base.add(const Duration(minutes: 35)), now: base), 'dans 35 min');
      expect(countdown(base.add(const Duration(hours: 3, minutes: 5)), now: base), 'dans 3 h 05');
      expect(countdown(base.add(const Duration(days: 2, hours: 4)), now: base), 'dans 2 j 4 h');
      expect(countdown(base.subtract(const Duration(hours: 3)), now: base), 'il y a 3 h');
      expect(clockTime(DateTime(2026, 11, 8, 17, 30)), '17:30');
    });
  });
}
