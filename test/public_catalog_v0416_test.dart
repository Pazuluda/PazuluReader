import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/source.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';

void main() {
  const site = CatalogSite('example', 'Example Manga',
    'https://example.org/', ['en'], SiteIntegration.website);

  const results = '''
    <html><head><title>Search Results</title></head><body>
      <nav><a href="/manga/solo-leveling">Solo Leveling</a></nav>
      <div class="page-item-detail">
        <h3 class="post-title"><a href="/manga/solo-leveling/">Solo Leveling</a></h3>
        <img data-src="/covers/solo.jpg"/>
      </div>
      <div class="page-item-detail">
        <h3 class="post-title"><a href="https://evil.example/manga/solo-leveling">Solo Leveling</a></h3>
      </div>
      <article><h3><a href="/manga/naruto/">Naruto</a></h3></article>
    </body></html>
  ''';

  test('recognizes only actual matching search cards on selected host', () {
    final parsed = parsePublicSearchHtml(results,
      site: site, sourceId: 'public_example', query: 'Solo Leveling');
    expect(parsed.length, 1);
    expect(parsed.single.title, 'Solo Leveling');
    expect(parsed.single.links.single.sourceId, 'public_example');
    expect(parsed.single.links.single.workId,
      'https://example.org/manga/solo-leveling/');
  });

  test('chapter links become native readers validated before display', () async {
    final adapter = PublicCatalogSource(site,
      fetchHtml: (url) async {
        if (url.queryParameters.containsKey('s')) return results;
        return '''<html><a href="/manga/solo-leveling/chapter-15/">Chapter 15</a>
          <a href="/manga/solo-leveling/chapter-16/">Chapter 16</a></html>''';
      });
    final found = await adapter.search('Solo Leveling');
    expect(found, hasLength(1));
    final chapters = await adapter.listChapters(found.single.links.single.workId,
      langs: ['en']);
    expect(chapters.length, 2);
    expect(chapters.every((c) => !c.isExternal), isTrue);
    expect(chapters.map((c) => c.key.id).toSet(), {'15', '16'});
    // A chapter page without any image is never turned into a fake page:
    // the engine asks for the hidden WebView2 renderer instead.
    final fetch = await adapter.fetchPages(chapters.first);
    expect(fetch.needsBrowser, isTrue);
    expect(fetch.pages, isEmpty);
    await expectLater(adapter.getPages(chapters.first), throwsA(isA<SourceException>()));
  });

  test('no made-up results on unsupported HTML layout', () {
    final found = parsePublicSearchHtml('<html><title>Solo Leveling</title></html>',
      site: site, sourceId: 'public_example', query: 'Solo Leveling');
    expect(found, isEmpty);
  });
}
