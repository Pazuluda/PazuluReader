import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_listing.dart';
import 'package:pazulu_reader/core/source_catalog.dart';

void main() {
  final site = CatalogSite('example', 'Exemple', 'https://manga.example.org/',
      ['fr'], SiteIntegration.website);

  test('une liste déroulante publique peut révéler les chapitres', () {
    final chapters = ChapterListingParser.parseListing('''
      <html><body><select id="chapters">
        <option value="/serie/chapter-12">Chapitre 12</option>
        <option value="/serie/chapter-13">Chapitre 13</option>
      </select></body></html>
    ''', pageUrl: 'https://manga.example.org/serie/', site: site);
    expect(chapters.length, 2);
    expect(chapters.last.key.number, 13);
  });

  test('les options hors domaine et les accès premium sont exclus', () {
    final chapters = ChapterListingParser.parseListing('''
      <html><body>
        <a href="https://evil.example.net/chapter-999">Chapitre 999</a>
        <option value="/serie/chapter-8" class="premium">Chapitre 8</option>
        <a href="/serie/chapter-6">Chapitre 6</a>
      </body></html>
    ''', pageUrl: 'https://manga.example.org/serie/', site: site);
    expect(chapters.length, 1);
    expect(chapters.single.key.number, 6);
  });
}
