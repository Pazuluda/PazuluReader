import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/models.dart';

void main() {
  test('merge precise duplicate series without downloading pages', () {
    final first = WorkInfo(
      id: 'one:123', title: 'Fiction Example',
      type: ContentType.manhwa, languages: const ['en'],
      links: const [SourceLink(sourceId: 'one', workId: '123')],
    );
    final second = WorkInfo(
      id: 'two:44', title: 'Fiction Example',
      description: 'Resume ajoute a partir de la seconde source',
      type: ContentType.manhwa, languages: const ['fr'],
      links: const [SourceLink(sourceId: 'two', workId: '44')],
    );
    final result = mergeSearchResults([first, second]);
    expect(result.length, 1);
    expect(result.single.links.length, 2);
    expect(result.single.languages.toSet(), {'en', 'fr'});
    expect(result.single.description, isNotEmpty);
  });

  test('manhwa and webtoon can merge under identical canonical title', () {
    final a = WorkInfo(id: 'a', title: 'Example', type: ContentType.manhwa);
    final b = WorkInfo(id: 'b', title: 'Example', type: ContentType.webtoon);
    expect(mergeSearchResults([a, b]).length, 1);
  });

  test('works with same name but different category stay separate', () {
    final a = WorkInfo(id: 'a', title: 'Example', type: ContentType.manga);
    final b = WorkInfo(id: 'b', title: 'Example', type: ContentType.webtoon);
    expect(mergeSearchResults([a, b]).length, 2);
  });
}
