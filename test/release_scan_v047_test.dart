import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/release_scan.dart';

void main() {
  SourceChapter chapter(String key, {String lang = 'en'}) => SourceChapter(
        sourceId: 'demo', chapterId: 'demo-$key', key: ChapterKey.parse(key),
        lang: lang, group: 'Demo', externalUrl: 'https://example.org/ch/$key',
      );
  test('unread available on initial check is distinct from new publication', () {
    final progress = ReadingProgress(lastKey: '15', lastPage: 1,
        readKeys: {'15'});
    final availability = ReadAvailability.calculate(progress, [
      chapter('1'), chapter('14'), chapter('15'), chapter('16'), chapter('17'),
    ]);
    expect(availability.total, 5);
    expect(availability.unread, 2);
    expect(availability.nextUnread, '16');
    expect(availability.latest, '17');
  });
  test('no reading history gives availability, not release notifications', () {
    final availability = ReadAvailability.calculate(ReadingProgress(), [
      chapter('12'), chapter('13'), chapter('13'),
    ]);
    expect(availability.total, 2);
    expect(availability.unread, 2);
    expect(availability.nextUnread, '12');
  });
  test('late translation works independently when supplied a language feed', () {
    final progress = ReadingProgress(lastKey: '20', readKeys: {'19', '20'});
    final en = ReadAvailability.calculate(progress, [chapter('21')]);
    final fr = ReadAvailability.calculate(progress, [chapter('18', lang: 'fr'),
      chapter('20', lang: 'fr'), chapter('21', lang: 'fr')]);
    expect(en.unread, 1);
    expect(fr.unread, 1);
    expect(fr.nextUnread, '21');
  });
  test('previous chapters stay read when old readKeys are incomplete', () {
    final progress = ReadingProgress(lastKey: '30');
    final r = ReadAvailability.calculate(progress, [chapter('10'), chapter('29'), chapter('30'), chapter('31')]);
    expect(r.unread, 2);
  });
}
