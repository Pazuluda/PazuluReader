import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/achievements.dart';
import 'package:pazulu_reader/core/library_insights.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/recap.dart';
import 'package:pazulu_reader/core/zip_writer.dart';

void main() {
  test('ZIP : CRC32 connu et structure valide', () {
    expect(ZipWriter.crc32('123456789'.codeUnits), 0xCBF43926);
    final zip = (ZipWriter()
          ..addText('a.txt', 'bonjour')
          ..addText('b.txt', 'é'))
        .build();
    final d = ByteData.sublistView(zip);
    expect(d.getUint32(0, Endian.little), 0x04034b50); // début de fichier
    expect(d.getUint32(zip.length - 22, Endian.little), 0x06054b50); // fin de répertoire
    expect(d.getUint16(zip.length - 22 + 10, Endian.little), 2); // 2 fichiers
  });

  test('défis du mois et récap de l\'année', () {
    final now = DateTime(2026, 11, 15);
    final log = ActivityLog();
    for (var day = 1; day <= 12; day++) {
      final d = log.days.putIfAbsent(ActivityLog.dayKey(DateTime(2026, 11, day)), DayActivity.new);
      d.chapters = 10;
      d.minutes = 50;
    }
    final history = [
      HistoryItem(workId: 'a', title: 'A', chapterId: '1', at: DateTime(2026, 11, 2), finished: true),
      HistoryItem(workId: 'b', title: 'B', chapterId: '1', at: DateTime(2026, 11, 3), finished: true),
      HistoryItem(workId: 'b', title: 'B', chapterId: '2', at: DateTime(2026, 11, 4), finished: true),
      HistoryItem(workId: 'c', title: 'C', chapterId: '9', at: DateTime(2026, 3, 4), finished: true),
    ];
    final entries = [
      LibraryEntry(work: const WorkInfo(id: 'b', title: 'B', tags: ['Action']), status: TrackStatus.completed)
        ..updatedAt = DateTime(2026, 11, 10),
    ];
    final ch = Recap.challenges(entries, log, history, now: now);
    expect(ch[0].value, 120);
    expect(ch[0].done, isTrue);
    expect(ch[1].value, 12);
    expect(ch[2].value, 2); // a et b commencées en novembre
    expect(ch[3].done, isTrue);

    final r = Recap.year(entries, log, history, year: 2026);
    expect(r.chapters, 120);
    expect(r.activeDays, 12);
    expect(r.bestStreak, 12);
    expect(r.bestMonth, 11);
    expect(r.topWorks.first, ('B', 2));
    expect(r.topGenre, 'Action');
    expect(r.newWorks, 3);
  });

  test('réglages 1.9.0 : enregistrés et relus', () {
    final s = Settings()
      ..startWithWindows = true
      ..followSystemTheme = true;
    final back = Settings.fromJson(s.toJson());
    expect(back.startWithWindows, isTrue);
    expect(back.followSystemTheme, isTrue);
    expect(Settings.fromJson(const {}).startWithWindows, isFalse);
  });
}
