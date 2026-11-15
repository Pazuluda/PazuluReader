import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/library_insights.dart';
import 'package:pazulu_reader/core/models.dart';

LibraryEntry entry(String id, String title, {TrackStatus status = TrackStatus.reading, DateTime? at,
    List<String> alt = const []}) =>
    LibraryEntry(work: WorkInfo(id: id, title: title, altTitles: alt), status: status)
      ..progress.updatedAt = at;

void main() {
  final now = DateTime(2026, 11, 15);

  test('lectures en cours pas ouvertes depuis 3 mois', () {
    final list = [
      entry('a', 'A', at: now.subtract(const Duration(days: 120))),
      entry('b', 'B', at: now.subtract(const Duration(days: 10))),
      entry('c', 'C', status: TrackStatus.completed, at: now.subtract(const Duration(days: 400))),
    ];
    expect(LibraryInsights.stale(list, now: now).map((e) => e.work.id), ['a']);
  });

  test('doublons : même titre écrit autrement, pas les titres différents, paires ignorées', () {
    final list = [
      entry('x1', 'The Beginning After The End'),
      entry('x2', 'Beginning After the End (Official)'),
      entry('y', 'Omniscient Reader'),
      entry('z', 'Solo Leveling', alt: ['Na Honjaman Level Up']),
      entry('z2', 'Na Honjaman Level Up'),
    ];
    final dups = LibraryInsights.duplicates(list);
    final ids = {for (final (a, b) in dups) LibraryInsights.pairId(a.work.id, b.work.id)};
    expect(ids, {'x1|x2', 'z|z2'});
    expect(LibraryInsights.duplicates(list, ignored: {'x1|x2'}).length, 1);
  });

  test('stats : rythme sur 8 semaines et temps pour rattraper', () {
    final e = entry('w', 'W')..progress.lastKey = '40';
    final history = [
      for (var i = 0; i < 16; i++)
        HistoryItem(workId: 'w', title: 'W', chapterId: '${25 + i}', at: now.subtract(Duration(days: i * 3)),
            finished: true),
    ];
    final st = LibraryInsights.statsFor(e, history, latest: 60, now: now);
    expect(st.perWeek, 2); // 16 chapitres en 8 semaines
    expect(st.remaining, 20);
    expect(st.weeksToCatchUp, 10);
  });

  test('historique : enregistré et relu', () {
    final h = HistoryItem(workId: 'w', title: 'W', chapterId: '12', at: now, finished: true);
    final back = HistoryItem.fromJson(h.toJson())!;
    expect(back.workId, 'w');
    expect(back.finished, isTrue);
    expect(HistoryItem.fromJson('x'), isNull);
  });
}
