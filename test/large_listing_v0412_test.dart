import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_listing.dart';
import 'package:pazulu_reader/core/source_catalog.dart';

void main() {
  test('a public index may contain more than 250 chapter links', () {
    final links = StringBuffer('<html><body>');
    for (var i = 1; i <= 610; i++) {
      links.write('<a href="/series/example/chapter-$i">Chapter $i</a>');
    }
    links.write('</body></html>');
    final found = ChapterListingParser.parseListing(links.toString(),
        pageUrl: 'https://manhuaus.com/series/example',
        site: catalogSiteById('manhuaus')!);
    expect(found.length, 610);
    expect(found.last.key.id, '610');
  });
}
