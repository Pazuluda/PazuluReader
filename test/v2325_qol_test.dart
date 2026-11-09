import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/achievements.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/schedule/mangaupdates.dart';
import 'package:pazulu_reader/core/work_status.dart';

void main() {
  test('MangaUpdates : sorties du jour (format réel de l\'API v1)', () {
    const raw = '''
{"total_hits":2,"page":1,"per_page":50,"results":[
 {"record":{"id":1291207,"title":"Seventh","volume":"5","chapter":"29a",
   "groups":[{"name":"seven7th scans","group_id":7264214211}],"release_date":"2026-11-08",
   "time_added":{"timestamp":1794180940}},
  "metadata":{"series":{"series_id":76419437034,"title":"Seventh",
   "url":"https://www.mangaupdates.com/series/z3u5qzu/seventh"}}},
 {"record":{"id":1291204,"title":null,"volume":null,"chapter":"27-28",
   "release_date":"2026-11-08"},
  "metadata":{"series":{"series_id":58560912178,"title":"Ougon no Keikenchi"}}}
]}''';
    final list = MangaUpdatesClient.parseDays(raw);
    expect(list.length, 2);
    expect(list[0].seriesTitle, 'Seventh');
    expect(list[0].chapter, '29');
    expect(list[0].date, DateTime(2026, 11, 8));
    expect(list[1].seriesTitle, 'Ougon no Keikenchi');
    expect(list[1].chapter, '28');
  });

  test('MangaUpdates : date la plus ancienne par chapitre, statut', () {
    const raw = '''
{"results":[
 {"record":{"chapter":"100","release_date":"2026-10-20"},"metadata":{"series":{"title":"X"}}},
 {"record":{"chapter":"100","release_date":"2026-10-18"},"metadata":{"series":{"title":"X"}}},
 {"record":{"chapter":"101","release_date":"2026-10-25"},"metadata":{"series":{"title":"X"}}}
]}''';
    final d = MangaUpdatesClient.parseReleaseDates(raw);
    expect(d['100'], DateTime(2026, 10, 18));
    expect(d['101'], DateTime(2026, 10, 25));
    expect(MangaUpdatesClient.parseStatus('{"status":"5 Volumes (Ongoing)","completed":true}'), 'Ongoing');
    expect(WorkStatusEngine.parse(MangaUpdatesClient.parseStatus('{"status":"120 Chapters (Hiatus)"}')),
        SeriesStatus.hiatus);
    expect(WorkStatusEngine.parse(MangaUpdatesClient.parseStatus('{"status":"Complete"}')),
        SeriesStatus.completed);
  });

  test('MangaUpdates : seule une série au même titre est retenue', () {
    const raw = '''
{"results":[
 {"record":{"series_id":1,"title":"Solo Leveling: Ragnarok"},"hit_title":"Solo Leveling: Ragnarok"},
 {"record":{"series_id":2,"title":"Na Honjaman Level Up"},"hit_title":"Solo Leveling"}
]}''';
    expect(MangaUpdatesClient.pickSeries(raw, ['Solo Leveling']), 2);
    expect(MangaUpdatesClient.pickSeries(raw, ['Omniscient Reader']), isNull);
  });

  test('succès : identifiants uniques, plus de 50', () {
    final ids = Achievements.all.map((a) => a.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, greaterThanOrEqualTo(50));
  });

  test('statistiques : 7 derniers jours, mois, meilleur mois', () {
    final now = DateTime(2026, 11, 9, 12);
    final log = ActivityLog();
    log.addChapters(10, at: DateTime(2026, 11, 8));
    log.addChapters(5, at: DateTime(2026, 11, 1));
    log.addChapters(40, at: DateTime(2026, 10, 3));
    final s = ReaderStats.compute(const [], log, now: now);
    expect(s.weekChapters, 10);
    expect(s.monthChapters, 15);
    expect(s.bestMonth, 40);
    expect(s.totalMinutes, 55 * 5);
  });

  test('réglages : choix de langue et recherches récentes conservés', () {
    final st = Settings(comicLangs: ['fr', 'en'], langChosen: true, recentSearches: ['solo', 'mythic']);
    final back = Settings.fromJson(st.toJson());
    expect(back.langChosen, isTrue);
    expect(back.comicLangs, ['fr', 'en']);
    expect(back.recentSearches, ['solo', 'mythic']);
    // Old settings file (2.3.24): the question will be asked once.
    expect(Settings.fromJson({'comicLangs': ['en', 'fr']}).langChosen, isFalse);
  });
}
