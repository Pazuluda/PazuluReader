import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/browser_navigation.dart';

void main() {
  group('URL de lecture integree', () {
    test('accepte les pages HTTPS de l editeur', () {
      expect(safeReadingUri('https://www.webnovel.com/book/123?chapter=16')?.host,
          'www.webnovel.com');
      expect(safeReadingUri(' https://mangadex.org/title/abc ').toString(),
          'https://mangadex.org/title/abc');
    });
    test('rejette les schemas non-web et les URLs dangereuses', () {
      for (final candidate in <String>[
        'javascript:alert(1)',
        'data:text/html,hi',
        'file:///C:/private.txt',
        'http://example.com/',
        'https://user:password@example.com/',
        'not-an-url',
        '',
      ]) {
        expect(safeReadingUri(candidate), isNull, reason: candidate);
      }
    });
  });
}
