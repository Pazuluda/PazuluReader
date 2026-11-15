import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/moments.dart';

void main() {
  test('réglages de lecture 1.6.0 : enregistrés et relus', () {
    final s = Settings()
      ..marathonMode = true
      ..readerDim = 0.3
      ..readerWarm = 0.8
      ..pageTrims['public_x'] = [1, 2];
    final back = Settings.fromJson(s.toJson());
    expect(back.marathonMode, isTrue);
    expect(back.readerDim, closeTo(0.3, 1e-9));
    expect(back.readerWarm, closeTo(0.8, 1e-9));
    expect(back.pageTrims['public_x'], [1, 2]);
  });

  test('anciens réglages : valeurs par défaut', () {
    final back = Settings.fromJson(const {});
    expect(back.marathonMode, isFalse);
    expect(back.readerDim, 0);
    expect(back.pageTrims, isEmpty);
  });

  test('moment : enregistré et relu', () {
    final m = Moment(
      work: const WorkInfo(id: 'w', title: 'Solo Leveling'),
      chapterId: ChapterKey.parse('120').id,
      chapterLabel: 'Chapitre 120',
      page: 14,
      at: DateTime(2026, 11, 15),
      note: 'Arise',
    );
    final back = Moment.fromJson(m.toJson())!;
    expect(back.key, m.key);
    expect(back.page, 14);
    expect(back.note, 'Arise');
    expect(Moment.fromJson({'oops': 1}), isNull);
  });
}
