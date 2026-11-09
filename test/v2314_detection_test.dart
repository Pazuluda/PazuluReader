import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_listing.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/engine/availability.dart';
import 'package:pazulu_reader/engine/validation/image_sniffer.dart';
import 'package:pazulu_reader/engine/validation/page_validation.dart';

const site = CatalogSite('test', 'Demo Reader', 'https://reader.example.org/',
    ['fr'], SiteIntegration.website);

PageProbe probe(int i, int w, int h) => PageProbe(index: i, url: 'https://cdn.example/$i.webp',
    status: 200, contentType: 'image/webp',
    sniff: ImageSniff(kind: PayloadKind.image, format: 'webp', width: w, height: h));

void main() {
  test('rimuscan : « Chapitre 248 » + « 28 oct » ne donne pas 24828', () {
    final result = ChapterListingParser.parseListing('''
      <html><head><title>Demo</title></head><body>
      <a href="/manga/twatf/chapitre-248/"><span>Chapitre 248</span><span>28 oct</span></a>
      <a href="/manga/twatf/chapitre-247/"><span>Chapitre 247</span><span>21 oct</span></a>
      </body></html>''', pageUrl: 'https://reader.example.org/manga/twatf/', site: site);
    expect(result.map((e) => e.key.id).toSet(), {'248', '247'});
  });

  test('pages lues dans le script : petite icône en fin de liste retirée, chapitre lisible', () {
    final pages = [for (var i = 0; i < 20; i++) PageRef('https://cdn.example/$i.webp')];
    final verdict = const PageValidationEngine().evaluate(pages,
        probes: [probe(0, 800, 2000), probe(1, 800, 2000), probe(19, 128, 128)],
        policy: const ValidationPolicy(minWidth: 300, minHeight: 40, verticalStrip: true),
        transport: 'html-script');
    expect(verdict.pages.length, 19);
    expect(verdict.readable, isTrue);
  });

  test('même petite image au milieu : chapitre toujours refusé', () {
    final pages = [for (var i = 0; i < 20; i++) PageRef('https://cdn.example/$i.webp')];
    final verdict = const PageValidationEngine().evaluate(pages,
        probes: [probe(0, 800, 2000), probe(10, 128, 128), probe(19, 800, 2000)],
        policy: const ValidationPolicy(minWidth: 300, minHeight: 40, verticalStrip: true),
        transport: 'html-script');
    expect(verdict.completeness, PageCompleteness.partial);
  });
}
