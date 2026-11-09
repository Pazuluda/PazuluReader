import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/sources/sushiscan.dart';

const series = 'https://sushiscan.net/catalogue/na-honjaman-level-up/';
const htmlSeries = '''
<html><head><title>Solo Leveling</title><meta property="og:image" content="https://sushiscan.net/cover.jpg"></head>
<body><h1>Solo Leveling</h1><div class="listing-chapters_wrap"><ul>
<li class="wp-manga-chapter"><a href="https://sushiscan.net/solo-leveling-chapitre-200/">Chapitre 200</a></li>
<li class="wp-manga-chapter"><a href="https://sushiscan.net/solo-leveling-chapitre-179-5/">Chapitre 179.5</a></li>
<li class="wp-manga-chapter"><a href="https://sushiscan.net/solo-leveling-vol-15/">Volume 15</a></li>
<li class="wp-manga-chapter"><a href="https://sushiscan.net/solo-leveling-vol-2/">Volume 2</a></li>
<li class="wp-manga-chapter"><a href="https://sushiscan.net/solo-leveling-vol-1/">Volume 1</a></li>
<li class="wp-manga-chapter"><a href="https://bad.example/ad/">Volume 9</a></li>
</ul></div></body></html>
''';
const htmlReader = '''
<html><body><div class="reading-content">
 <div class="page-break"><img data-src="https://cdn.example.org/solo/page-01.jpg" src="data:image/gif;base64,x"></div>
 <div class="page-break"><img src="https://cdn.example.org/solo/page-02.jpg"></div>
 <div class="page-break"><img src="https://cdn.example.org/solo/page-02.jpg"></div>
</div><img src="https://cdn.example.org/ad.jpg"></body></html>
''';

void main() {
  test('Volumes distincts des chapitres et ordre numérique', () {
    final v2 = ChapterKey.parse('Volume 2');
    final ch2 = ChapterKey.parse('Chapitre 2');
    expect(v2.id, 'volume-2');
    expect(v2.longLabel, 'Volume 2');
    expect(ch2.id, '2');
    expect(v2 == ch2, isFalse);
    expect(ChapterKey.parse('vol 15').compareTo(v2), greaterThan(0));
  });

  test('Fiche et liens chapitres/volumes sont parsés sans pub externe', () {
    final w = SushiScanSource.parseWork(htmlSeries, series);
    expect(w.title, 'Solo Leveling');
    final chapters = SushiScanSource.parseChapters(htmlSeries, series);
    expect(chapters.length, 5);
    expect(chapters.any((c) => c.key.id == 'volume-2'), isTrue);
    expect(chapters.any((c) => c.key.id == '179.5'), isTrue);
    expect(chapters.every((c) => c.lang == 'fr'), isTrue);
    expect(chapters.every((c) => c.chapterId.startsWith('https://sushiscan.net/')), isTrue);
  });

  test('Images récupérées uniquement dans la zone de lecture', () {
    final pages = SushiScanSource.parsePages(htmlReader, 'https://sushiscan.net/solo-leveling-vol-2/');
    expect(pages.length, 2);
    expect(pages[0].url, 'https://cdn.example.org/solo/page-01.jpg');
    expect(pages[1].url, 'https://cdn.example.org/solo/page-02.jpg');
  });

  test('Recherche puis lecture métadonnées sans serveur externe', () async {
    final seen = <String>[];
    final source = SushiScanSource(client: MockClient((request) async {
      seen.add(request.url.toString());
      if (request.url.queryParameters['s'] == 'Solo Leveling') {
        return http.Response('''<article class="page-item-detail"><h3 class="post-title">
          <a href="$series">Solo Leveling</a></h3></article>''', 200);
      }
      if (request.url.toString() == series) return http.Response(htmlSeries, 200);
      if (request.url.path == '/solo-leveling-vol-2/') return http.Response('''<html><a href="$series">Revenir à la fiche Solo Leveling</a>$htmlReader</html>''', 200);
      return http.Response('unknown', 404);
    }));
    final byUrl = await source.seriesFromChapterUrl('https://sushiscan.net/solo-leveling-vol-2/');
    expect(byUrl.title, 'Solo Leveling');
    // Resolving a pasted chapter URL intentionally requests its HTML once.
    // Start a fresh request log to verify that subsequent catalogue browsing
    // does not request any chapter page before the user clicks Read.
    seen.clear();
    final works = await source.search('Solo Leveling');
    expect(works.length, 1);
    final chapters = await source.listChapters(works.single.links.single.workId,
      langs: const ['fr']);
    expect(chapters.length, 5);
    expect(seen.where((u) => u.contains('vol-2')).isEmpty, isTrue,
        reason: 'Pas de téléchargement de page pendant la recherche de chapitres');
    final vol2 = chapters.singleWhere((c) => c.key.id == 'volume-2');
    final pages = await source.getPages(vol2);
    expect(pages.length, 2);
    expect(seen.any((u) => u.contains('vol-2')), isTrue);
  });
}
