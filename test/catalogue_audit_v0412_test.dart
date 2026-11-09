import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/catalogue_audit.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';

SourceChapter chapter(String source, String number, {bool external = false}) =>
  SourceChapter(sourceId: source, chapterId: '$source:$number',
    key: ChapterKey.parse(number), lang: 'en', group: source,
    externalUrl: external ? 'https://example.org/chapitre/$number' : null);

void main() {
  test('a failed catalogue retains previously seen chapters', () {
    final old = chapter('mangadex', '164.2');
    final chapters = mergeObservedChapters(previous: [old],
      successful: const {}, failed: {'mangadex'}, local: const <SourceChapter>[]);
    expect(chapters.map((v) => v.key.id), ['164.2']);
  });

  test('successful empty catalogue clears obsolete entries', () {
    final old = chapter('mangadex', '164.2');
    final chapters = mergeObservedChapters(previous: [old],
      successful: {'mangadex': const []}, failed: const <String>{}, local: const <SourceChapter>[]);
    expect(chapters, isEmpty);
  });

  test('chapter from an extra linked HTML catalogue stays external only', () {
    final chapters = mergeObservedChapters(previous: const <SourceChapter>[],
      successful: {
        'mangadex': [chapter('mangadex', '1')],
        'listing:scanmanga:1234': [chapter('listing:scanmanga:1234', '800', external: true)],
      }, failed: const <String>{}, local: const <SourceChapter>[]);
    expect(chapters.length, 2);
    expect(chapters.singleWhere((c) => c.key.id == '800').isExternal, isTrue);
  });

  test('cached variants are not duplicated when local chapter exists', () {
    final cached = chapter('mangadex', '5');
    final chapters = mergeObservedChapters(previous: [cached],
      successful: {'mangadex': [cached]}, failed: const <String>{}, local: [cached]);
    expect(chapters.length, 1);
  });

  test('failure and unavailable status are not successful checks', () {
    const a = CatalogueCheck(sourceId: 'a', name: 'A',
      state: CatalogueCheckState.failed, observed: 0, readable: 0, retained: 2);
    const b = CatalogueCheck(sourceId: 'b', name: 'B',
      state: CatalogueCheckState.unsupported, observed: 0, readable: 0);
    expect(a.confirmed, isFalse);
    expect(b.confirmed, isFalse);
    expect(a.retained, 2);
  });
}
