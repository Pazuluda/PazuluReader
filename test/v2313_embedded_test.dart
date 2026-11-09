import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/source.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';
import 'package:pazulu_reader/engine/http/html_extract.dart';

void main() {
  final base = Uri.parse('https://site.example/series/abc/chapter-255');

  test('images du chapitre lues dans le JSON de la page (Next.js)', () {
    const raw = '<html><body><div id="__next"></div><img src="/logo.png">'
        '<script id="__NEXT_DATA__" type="application/json">{"props":{"pages":['
        '"https:\\/\\/cdn.example\\/ch\\/255\\/01.webp","https:\\/\\/cdn.example\\/ch\\/255\\/02.webp",'
        '"https:\\/\\/cdn.example\\/ch\\/255\\/03.webp","https:\\/\\/cdn.example\\/ch\\/255\\/04.webp"],'
        '"cover":"https:\\/\\/cdn.example\\/covers\\/abc.webp"}}</script></body></html>';
    final images = HtmlExtract.embeddedImages(raw, base);
    expect(images, [
      'https://cdn.example/ch/255/01.webp',
      'https://cdn.example/ch/255/02.webp',
      'https://cdn.example/ch/255/03.webp',
      'https://cdn.example/ch/255/04.webp',
    ]);
  });

  test('chapitre dessiné en JavaScript : lu par notre lecteur, sans navigateur', () {
    const site = CatalogSite('directory_125', 'solaris-scans.fr', 'https://site.example/', ['fr'],
        SiteIntegration.website);
    final source = PublicCatalogSource(site, fetchHtml: (_) async => '');
    final pages = [for (var i = 1; i <= 6; i++) '"/uploads/abc/255/$i.jpg"'].join(',');
    final fetch = source.parsePageFetch(
        '<html><body><div id="app"></div><script>window.__DATA__={"images":[$pages]}</script>'
        '</body></html>', base);
    expect(fetch.needsBrowser, isFalse);
    expect(fetch.pages.length, 6);
    expect(fetch.pages.first.url, 'https://site.example/uploads/abc/255/1.jpg');
  });

  test('moins de 3 images : rien d\'inventé', () {
    expect(HtmlExtract.embeddedImages('<script>{"a":"https://x.example/a/1.jpg"}</script>', base),
        isEmpty);
  });

  test('page payante avec images dans le script : jamais prise pour le chapitre', () {
    const site = CatalogSite('directory_126', 'Demo', 'https://site.example/', ['fr'],
        SiteIntegration.website);
    final source = PublicCatalogSource(site, fetchHtml: (_) async => '');
    final pages = [for (var i = 1; i <= 6; i++) '"/uploads/abc/255/$i.jpg"'].join(',');
    expect(() => source.parsePageFetch(
        '<html><body><p>Ce chapitre est réservé aux abonnés. Abonnez-vous pour lire la suite.</p>'
        '<script>window.__DATA__={"images":[$pages]}</script></body></html>', base),
        throwsA(isA<SourceException>()));
  });
}
