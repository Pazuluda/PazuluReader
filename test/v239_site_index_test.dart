import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/site_index.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';

void main() {
  test('titre normalisé : accents, ponctuation, slug', () {
    expect(SiteTitleIndex.norm('Return of the Frozen Player!'), 'return of the frozen player');
    expect(SiteTitleIndex.norm('Pokémon : Épisode'), 'pokemon episode');
    expect(SiteTitleIndex.norm(IndexedTitle.titleFromSlug('disastrous-necromancer')),
        'disastrous necromancer');
  });

  test('une œuvre retrouve TOUS les sites qui la listent, aucun en premier', () async {
    final idx = SiteTitleIndex(null);
    await idx.put('public_a', const [IndexedTitle('One Piece', 'https://a.example/manga/one-piece/')]);
    await idx.put('public_b', const [IndexedTitle('ONE PIECE', 'https://b.example/manga/op/')]);
    await idx.put('public_c', const [IndexedTitle('One Punch Man', 'https://c.example/manga/opm/')]);
    final links = idx.linksFor(['One Piece']);
    expect(links.map((l) => l.sourceId).toSet(), {'public_a', 'public_b'});
    await idx.prepareWorks();
    final works = idx.works!;
    expect(works.length, 2);
    expect(works.firstWhere((w) => w.key == 'one piece').links.length, 2);
  });

  test('catalogue Madara lu par l\'API WordPress (100 par page)', () async {
    const site = CatalogSite('directory_900', 'Demo', 'https://demo.example/', ['en'],
        SiteIntegration.website);
    final source = PublicCatalogSource(site, fetchHtml: (uri) async {
      if (uri.path == '/wp-json/wp/v2/wp-manga') {
        return '[{"link":"https://demo.example/manga/alpha/","title":{"rendered":"Alpha &#038; Beta"}},'
            '{"link":"https://demo.example/manga/b/","title":{"rendered":"Bravo"}}]';
      }
      throw Exception('404');
    });
    final titles = await source.catalogueTitles();
    // Fewer than 10 from the API: list-mode and sitemaps are tried too
    // (they fail here), the API titles are kept.
    expect(titles.map((t) => t.title), containsAll(['Alpha & Beta', 'Bravo']));
  });

  test('catalogue MangaThemesia lu sur la page list-mode', () async {
    const site = CatalogSite('directory_901', 'Demo', 'https://demo.example/', ['fr'],
        SiteIntegration.website);
    final items = [
      for (var i = 0; i < 12; i++)
        '<li><a class="series" href="https://demo.example/manga/serie-$i/">Série $i</a></li>',
    ].join();
    final source = PublicCatalogSource(site, fetchHtml: (uri) async {
      if (uri.path == '/manga/list-mode/') return '<div class="soralist"><ul>$items</ul></div>';
      throw Exception('404');
    });
    final titles = await source.catalogueTitles();
    expect(titles.length, 12);
    expect(titles.first.url, startsWith('https://demo.example/manga/serie-'));
  });

  test('site map : adresses de séries seulement, titres rebâtis', () async {
    const site = CatalogSite('directory_902', 'Demo', 'https://demo.example/', ['en'],
        SiteIntegration.website);
    final source = PublicCatalogSource(site, fetchHtml: (uri) async {
      if (uri.path == '/wp-sitemap.xml') {
        return '<sitemapindex><sitemap><loc>https://demo.example/wp-sitemap-posts-wp-manga-1.xml</loc></sitemap></sitemapindex>';
      }
      if (uri.path == '/wp-sitemap-posts-wp-manga-1.xml') {
        return '<urlset><url><loc>https://demo.example/manga/solo-leveling/</loc></url>'
            '<url><loc>https://demo.example/manga/solo-leveling/chapter-1/</loc></url></urlset>';
      }
      throw Exception('404');
    });
    final titles = await source.catalogueTitles();
    expect(titles.map((t) => t.title), ['Solo Leveling']);
    expect(titles.single.fromSlug, isTrue);
  });

  test('re-lecture d\'un site : ses anciens titres sont remplacés', () async {
    final idx = SiteTitleIndex(null);
    await idx.put('public_a', const [IndexedTitle('Alpha', 'https://a.example/manga/alpha/')]);
    await idx.put('public_a', const [IndexedTitle('Beta', 'https://a.example/manga/beta/')]);
    expect(idx.linksFor(['Alpha']), isEmpty);
    expect(idx.linksFor(['Beta']).single.workId, 'https://a.example/manga/beta/');
    expect(idx.titleCount, 1);
  });

  test('titre écrit un peu autrement : site retrouvé (« The » en moins, « (Official) »)', () async {
    final idx = SiteTitleIndex(null);
    await idx.put('public_a', const [IndexedTitle('World After the Fall', 'https://a.example/manga/twatf/')]);
    await idx.put('public_b', const [IndexedTitle('The World After the Fall (Official)', 'https://b.example/manga/x/')]);
    await idx.put('public_c', const [IndexedTitle('The World Before the Fall', 'https://c.example/manga/y/')]);
    final ids = idx.linksFor(['The World After the Fall']).map((l) => l.sourceId).toSet();
    expect(ids, {'public_a', 'public_b'});
  });

  test('moins de 30 séries lues : le site n\'est pas considéré comme entièrement connu', () async {
    final idx = SiteTitleIndex(null);
    await idx.put('public_a', [for (var i = 0; i < 12; i++) IndexedTitle('T$i', 'https://a.example/manga/t$i/')]);
    expect(idx.covers('public_a'), isFalse);
    await idx.put('public_b', [for (var i = 0; i < 40; i++) IndexedTitle('T$i', 'https://b.example/manga/t$i/')]);
    expect(idx.covers('public_b'), isTrue);
  });
}
