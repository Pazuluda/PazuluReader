import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_consensus.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';

final now = DateTime(2026, 11, 15);

List<SourceChapter> site(String id, int to, {String lang = 'en', bool dated = true}) => [
      for (var i = 1; i <= to; i++)
        SourceChapter(sourceId: id, chapterId: '$id-$i', key: ChapterKey.parse('$i'),
            lang: lang, group: id, pages: 3,
            // Same chapter = same release date everywhere (chapter 75 four
            // days ago, weekly); French one week later.
            publishedAt: dated
                ? now.subtract(Duration(days: 4 + 7 * (75 - i) - (lang == 'fr' ? 7 : 0)))
                : null),
    ];

void main() {
  test('liste finale : le roman (201 ch., sans dates) d\'un seul site est masqué face au '
      'webtoon (72–75) sur 4 sites à jour', () {
    final all = [
      ...site('novel', 201, dated: false),
      ...site('manganato', 75),
      ...site('mangabats', 75),
      ...site('mangakakalot', 75),
      ...site('mangaread', 74),
      ...site('origines', 71, lang: 'fr'),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.sourceId == 'novel'), isEmpty);
    final maxEn = out.where((c) => c.lang == 'en').map((c) => c.key.number!).reduce((a, b) => a > b ? a : b);
    expect(maxEn, 75);
    expect(out.where((c) => c.lang == 'fr').length, 71);
    expect(notes.any((n) => n.sourceId == 'novel'), isTrue);
  });

  test('copie hors ligne : jamais masquée', () {
    final all = [
      ...site('local', 201, dated: false),
      ...site('a', 75),
      ...site('b', 75),
      ...site('c', 75),
      ...site('d', 74),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.sourceId == 'local').length, 201);
  });
}
