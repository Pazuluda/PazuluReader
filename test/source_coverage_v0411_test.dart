import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_inventory.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/models.dart';

SourceChapter entry(String id, String lang, {bool external = false,
  String source = 'mangadex'}) => SourceChapter(
    sourceId: source,
    chapterId: '$source-$id-$lang',
    key: ChapterKey.parse(id), lang: lang, group: source,
    externalUrl: external ? 'https://example.com/$id' : null,
  );

WorkInfo work(String title, {List<String> aliases = const [],
    ContentType type = ContentType.manhwa}) => WorkInfo(
  id: title, title: title, type: type, altTitles: aliases,
);

void main() {
  test('partial catalogue does not invent thousands of missing chapters', () {
    final chapters = groupChapters([
      entry('1', 'en'), entry('1197', 'en'),
      entry('4', 'fr', external: true), entry('1197', 'fr', external: true),
    ]);
    final en = inventoryForLanguage(chapters, 'en');
    final fr = inventoryForLanguage(chapters, 'fr');
    expect(en.listed, 2);
    expect(en.latestLabel, 'Ch. 1197');
    expect(en.readable, 2);
    expect(fr.listed, 2);
    expect(fr.readable, 0);
    expect(fr.externalOnly, 2);
  });

  test('language summary deduplicates sources with the same chapter', () {
    final chapters = groupChapters([
      entry('15', 'en'), entry('15', 'en', source: 'other'),
      entry('16', 'en', external: true),
    ]);
    final en = inventoryForLanguage(chapters, 'en');
    expect(en.listed, 2);
    expect(en.readable, 1);
    expect(en.externalOnly, 1);
    expect(en.sourceCount, 2);
  });

  test('auto-match uses exact primary or alternative titles, not fuzzy', () {
    expect(sameWorkAcrossSources(work('Solo Leveling', aliases: ['Only I Level Up']),
        work('Only I Level Up')), isTrue);
    expect(sameWorkAcrossSources(work('One Piece'), work('One Piece: Red')), isFalse);
    expect(sameWorkAcrossSources(work('One Piece'),
        work('One Piece', type: ContentType.anime)), isFalse);
  });
}
