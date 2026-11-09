import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';

void main() {
  test('MangaNato : liste complète et dates lues depuis la liste JSON de la page', () async {
    const site = CatalogSite('directory_055', 'manganato.gg', 'https://www.manganato.gg/', ['en'],
        SiteIntegration.website);
    const page = '''<html><body>
<div id="chapter-list-container" data-comic-slug="catastrophic-necromancer"
 data-api-url="https://www.manganato.gg/api/manga/__SLUG__/chapters"
 data-chapter-url-template="https://www.manganato.gg/manga/__MANGA__/__CHAPTER__"></div>
<a href="https://www.manganato.gg/manga/catastrophic-necromancer/chapter-319">Newest Chapter</a>
</body></html>''';
    final source = PublicCatalogSource(site, fetchHtml: (uri) async {
      if (uri.path == '/api/manga/catastrophic-necromancer/chapters') {
        final offset = int.parse(uri.queryParameters['offset'] ?? '0');
        if (offset > 0) return '{"success":true,"data":{"chapters":[]}}';
        final items = [
          for (var n = 319; n >= 300; n--)
            '{"chapter_name":"Chapter $n","chapter_slug":"chapter-$n",'
                '"updated_at":"2026-11-0${n == 319 ? 7 : 1}T10:00:00Z"}',
        ].join(',');
        return '{"success":true,"data":{"chapters":[$items]}}';
      }
      return page;
    });
    final list = await source.listChapters(
        'https://www.manganato.gg/manga/catastrophic-necromancer', langs: const ['en']);
    expect(list.length, 20);
    final top = list.firstWhere((c) => c.key.id == '319');
    expect(top.chapterId, 'https://www.manganato.gg/manga/catastrophic-necromancer/chapter-319');
    expect(top.publishedAt, DateTime.utc(2026, 11, 7, 10).toLocal());
  });
}
