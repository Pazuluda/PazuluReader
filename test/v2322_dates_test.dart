import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/schedule/weekly_schedule.dart';
import 'package:pazulu_reader/ui/format.dart';

void main() {
  test('date d\'un chapitre : le site qui l\'a sorti en premier', () {
    final history = <String, SeriesHistory>{};
    WeeklyScheduleBuilder.record(history, title: 'Catastrophic Necromancer', lang: 'en',
        at: DateTime(2026, 11, 6, 18), label: '319');
    WeeklyScheduleBuilder.record(history, title: 'Catastrophic Necromancer', lang: 'en',
        at: DateTime(2026, 11, 5, 9), label: '319');
    WeeklyScheduleBuilder.record(history, title: 'Catastrophic Necromancer', lang: 'en',
        at: DateTime(2026, 11, 7, 9), label: '319');
    final h = history.values.single;
    expect(DateTime.parse(h.chapterDates['319']!), DateTime(2026, 11, 5, 9));
    final again = SeriesHistory.fromJson(h.toJson())!;
    expect(again.chapterDates['319'], h.chapterDates['319']);
  });

  test('« Repéré » quand aucun site n\'écrit la date', () {
    final now = DateTime(2026, 11, 9, 12);
    expect(releaseLine(DateTime(2026, 11, 8, 12), now: now, verb: 'Repéré'), 'Repéré il y a 1 j');
  });
}
