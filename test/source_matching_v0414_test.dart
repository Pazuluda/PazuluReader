import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/models.dart';

void main() {
  test('a manhwa can be labelled webtoon on a second source', () {
    final first = WorkInfo(id: 'a', title: 'Solo Leveling',
      type: ContentType.manhwa);
    final other = WorkInfo(id: 'b', title: 'Only I Level Up',
      altTitles: const ['Solo Leveling'], type: ContentType.webtoon);
    expect(sameWorkAcrossSources(first, other), true);
  });
  test('identical work title does not mix novels and comics', () {
    final manga = WorkInfo(id: 'a', title: 'Solo Leveling',
      type: ContentType.manhwa);
    final novel = WorkInfo(id: 'b', title: 'Solo Leveling',
      type: ContentType.novel);
    expect(sameWorkAcrossSources(manga, novel), false);
  });
  test('different titles remain separate without exact alias', () {
    final a = WorkInfo(id:'a',title:'Solo Leveling',type: ContentType.manhwa);
    final b = WorkInfo(id:'b',title:'Solo Farming',type: ContentType.webtoon);
    expect(sameWorkAcrossSources(a,b), false);
  });
}
