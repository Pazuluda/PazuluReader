import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/schedule/mangaupdates.dart';

void main() {
  test('MangaUpdates : titre et autres noms d\'une série', () {
    const raw = '{"series_id": 1, "title": "The Second Coming of Gluttony", "associated": ['
        '{"title": "The Second Coming of Avarice"}, {"title": "탐식의 재림"}, {"title": " "}]}';
    expect(MangaUpdatesClient.parseNames(raw),
        ['The Second Coming of Gluttony', 'The Second Coming of Avarice', '탐식의 재림']);
    expect(MangaUpdatesClient.parseNames('oops'), isEmpty);
  });
}
