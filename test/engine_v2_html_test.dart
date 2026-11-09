import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source.dart';
import 'package:pazulu_reader/core/sources/sushiscan.dart';
import 'package:pazulu_reader/engine/availability.dart';
import 'package:pazulu_reader/engine/http/engine_http.dart';
import 'package:pazulu_reader/engine/http/html_extract.dart';
import 'package:pazulu_reader/extensions/manifest.dart';
import 'package:pazulu_reader/extensions/runtime/declarative_source.dart';

import 'engine_v2_support.dart';

ExtensionManifest manifest({String id = 'pazulu.test', List<String> hosts = const ['manhuaus.com'],
    String transport = 'html', String family = 'madara', Map<String, dynamic> extra = const {},
    List<String> types = const ['manhua']}) =>
    ExtensionManifest.parse({
      'schemaVersion': 2,
      'id': id,
      'name': 'Test',
      'version': '1.0.0',
      'languages': ['en'],
      'contentTypes': types,
      'hosts': hosts,
      'capabilities': {'search': true, 'chapters': true, 'pages': true},
      'transport': transport,
      'minimumEngineVersion': '2.0.0',
      'html': {'family': family, ...extra},
    });

DeclarativeHtmlSource source(ExtensionManifest m, [http.Client? client]) =>
    DeclarativeHtmlSource(m, EngineHttpClient(
        client: client ?? MockClient((_) async => http.Response('', 404)),
        checkDns: false));

void main() {
  group('Test A — Solo Leveling / SushiScan', () {
    const chapterUrl = 'https://sushiscan.net/solo-leveling-chap-198/';

    test('les 14 pages du lecteur ts_reader sont récupérées dans l\'ordre', () {
      final pages = SushiScanSource.parsePages(fixture('sushiscan_ts_reader_14.html'), chapterUrl);
      expect(pages, hasLength(14));
      expect(pages.first.url, 'https://cdn.sushiscan.example/solo/198/01.webp');
      expect(pages.last.url, 'https://cdn.sushiscan.example/solo/198/14.webp');
      for (var i = 0; i < 14; i++) {
        expect(pages[i].url, endsWith('/${(i + 1).toString().padLeft(2, '0')}.webp'));
      }
    });

    test('total annoncé détecté, lecture native sans WebView', () async {
      final s = SushiScanSource(client: MockClient((request) async =>
          http.Response(fixture('sushiscan_ts_reader_14.html'), 200,
              headers: {'content-type': 'text/html; charset=utf-8'})));
      final fetch = await s.fetchPages(SourceChapter(sourceId: 'sushiscan_net',
          chapterId: chapterUrl, key: ChapterKey.parse('198'), lang: 'fr',
          group: 'SushiScan.net'));
      expect(fetch.announcedTotal, 14);
      expect(fetch.pages, hasLength(14));
      expect(fetch.needsBrowser, isFalse);
      expect(fetch.imageHeaders['Referer'], chapterUrl);
    });

    test('8 images pour 14 annoncées : jamais présenté comme réussi', () async {
      final s = SushiScanSource(client: MockClient((request) async =>
          http.Response(fixture('sushiscan_ts_reader_8_of_14.html'), 200)));
      final chapter = SourceChapter(sourceId: 'sushiscan_net', chapterId: chapterUrl,
          key: ChapterKey.parse('198'), lang: 'fr', group: 'SushiScan.net');
      final fetch = await s.fetchPages(chapter);
      expect(fetch.announcedTotal, 14);
      expect(fetch.pages, hasLength(8));
      expect(fetch.needsBrowser, isTrue,
          reason: 'Le moteur doit passer par le rendu invisible, pas afficher 8/14.');
      await expectLater(s.getPages(chapter), throwsA(isA<SourceException>()));
    });

    test('aucun total codé en dur : 20 pages annoncées par un autre chapitre', () {
      final doc = html_parser.parse(fixture('paged_horizontal_manga.html'));
      final m = manifest(hosts: const ['cdn.example.org'], family: 'custom',
          transport: 'browser', extra: {'pageImages': ['#readerarea img']});
      final fetch = source(m).parsePageFetch(doc, fixture('paged_horizontal_manga.html'),
          Uri.parse('https://cdn.example.org/manga/onepiece/1/'));
      expect(fetch.announcedTotal, 20);
      expect(fetch.needsBrowser, isTrue);
    });
  });

  group('Test B/C — pages de restriction', () {
    test('Manga UP! « no longer free » : ChapterRestrictedException, pas de planche', () {
      final m = manifest(id: 'pazulu.mangaup', hosts: const ['mangaup.example'],
          family: 'custom', types: const ['manga'], extra: {'pageImages': ['.viewer img']});
      final raw = fixture('mangaup_no_longer_free.html');
      expect(
        () => source(m).parsePageFetch(html_parser.parse(raw), raw,
            Uri.parse('https://mangaup.example/series/1/115-1')),
        throwsA(isA<ChapterRestrictedException>()
            .having((e) => e.kind, 'kind', AccessKind.subscriptionRequired)),
      );
    });

    test('K MANGA : vérification d\'âge reconnue, cookies ignorés comme verdict', () {
      final m = manifest(id: 'pazulu.kmanga', hosts: const ['kmanga.example'],
          family: 'custom', types: const ['manga'], extra: {'pageImages': ['.reader img']});
      final raw = fixture('kmanga_age_gate.html');
      expect(
        () => source(m).parsePageFetch(html_parser.parse(raw), raw,
            Uri.parse('https://kmanga.example/title/1/episode/140')),
        throwsA(isA<ChapterRestrictedException>()
            .having((e) => e.kind, 'kind', AccessKind.ageVerification)),
      );
    });
  });

  group('Test E — familles de sites', () {
    test('Madara : images lazy-load (data-src, data-lazy-src, srcset, picture)', () {
      final raw = fixture('madara_lazy_chapter.html');
      final fetch = source(manifest()).parsePageFetch(html_parser.parse(raw), raw,
          Uri.parse('https://manhuaus.com/manga/martial-peak/chapter-12/'));
      expect(fetch.pages.map((p) => p.url).toList(), [
        'https://img.manhuaus.com/manga/mp/12/01.jpg',
        'https://img.manhuaus.com/manga/mp/12/02.jpg',
        'https://img.manhuaus.com/manga/mp/12/03-1600.jpg',
        'https://img.manhuaus.com/manga/mp/12/04.webp',
        'https://img.manhuaus.com/manga/mp/12/05.jpg',
      ]);
      expect(fetch.access, AccessKind.open, reason: 'bandeau cookies + vraies pages');
      expect(fetch.announcedTotal, isNull, reason: 'aucun total publié : non confirmé');
      expect(fetch.policy.verticalStrip, isTrue);
    });

    test('webtoon vertical : 40 tranches dans l\'ordre', () {
      final raw = fixture('webtoon_vertical.html');
      final m = manifest(hosts: const ['cdn.example.org'], types: const ['webtoon']);
      final fetch = source(m).parsePageFetch(html_parser.parse(raw), raw,
          Uri.parse('https://cdn.example.org/webtoon/ep9/'));
      expect(fetch.pages, hasLength(40));
      expect(fetch.pages[9].url, endsWith('/010.jpg'));
    });

    test('chapitre chargé par JavaScript : WebView2 si autorisé, sinon erreur claire', () {
      final raw = fixture('js_rendered_empty.html');
      final url = Uri.parse('https://manhuaus.com/manga/x/chapter-5/');
      final browser = source(manifest(transport: 'browser'))
          .parsePageFetch(html_parser.parse(raw), raw, url);
      expect(browser.needsBrowser, isTrue);
      expect(() => source(manifest()).parsePageFetch(html_parser.parse(raw), raw, url),
          throwsA(isA<SourceException>()));
    });

    test('webnovel textuel : aucune fausse planche générée', () {
      final raw = fixture('webnovel_text_chapter.html');
      expect(() => source(manifest(types: const ['webnovel'])).parsePageFetch(
          html_parser.parse(raw), raw, Uri.parse('https://manhuaus.com/novel/slime/140/')),
          throwsA(isA<SourceException>()));
    });

    test('liste de chapitres : décimaux, extra, bonus de volume, hors domaine exclu', () {
      final raw = fixture('madara_series.html');
      final chapters = source(manifest()).parseChapters(html_parser.parse(raw),
          Uri.parse('https://manhuaus.com/manga/martial-peak/'));
      expect(chapters.map((c) => c.key.id).toSet(),
          {'116', '115.5', '115.2', '115.1', '115', 'extra-1', 'volume-12-bonus'});
      expect(chapters.every((c) => c.chapterId.startsWith('https://manhuaus.com/')), isTrue);
      final bonus = chapters.singleWhere((c) => c.key.id == 'volume-12-bonus');
      expect(bonus.volume, '12');
    });

    test('recherche Madara : fiches seulement, ni chapitres ni autre domaine', () {
      final doc = html_parser.parse(fixture('madara_search.html'));
      final works = source(manifest()).parseSearch(doc);
      expect(works, hasLength(1));
      expect(works.single.title, 'Martial Peak');
      expect(works.single.links.single.workId, 'https://manhuaus.com/manga/martial-peak/');
      expect(works.single.coverUrl, 'https://manhuaus.com/cover/mp-193.jpg');
    });

    test('ts_reader protégé ou absent : pas d\'invention', () {
      expect(HtmlExtract.tsReader('<html></html>'), isNull);
      expect(HtmlExtract.tsReader('ts_reader.run({"sources":[]});')!.primary, isEmpty);
      expect(HtmlExtract.looksProtected('<div id="chapter-protector-data">'), isTrue);
    });
  });

  group('Client HTTP du moteur', () {
    test('changement de domaine : redirection refusée et signalée', () async {
      final client = EngineHttpClient(checkDns: false, client: MockClient((r) async =>
          http.Response('', 301, headers: {'location': 'https://new-domain.example/x'})));
      await expectLater(
        client.get(Uri.parse('https://old-domain.example/x'),
            allowedHosts: const ['old-domain.example']),
        throwsA(isA<SourceException>().having((e) => e.message, 'message',
            contains('changé de domaine'))),
      );
    });

    test('HTTP 429 : Retry-After respecté, circuit ouvert, pas de relance', () async {
      var calls = 0;
      final client = EngineHttpClient(checkDns: false, client: MockClient((r) async {
        calls++;
        return http.Response('slow down', 429, headers: {'retry-after': '120'});
      }));
      await expectLater(
        client.get(Uri.parse('https://api.example/x')),
        throwsA(isA<ChapterRestrictedException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 120))),
      );
      expect(calls, 1);
      await expectLater(client.get(Uri.parse('https://api.example/y')),
          throwsA(isA<ChapterRestrictedException>()));
      expect(calls, 1, reason: 'le circuit ouvert évite toute nouvelle requête');
    });

    test('source hors ligne : deux nouvelles tentatives bornées', () async {
      var calls = 0;
      final client = EngineHttpClient(checkDns: false, client: MockClient((r) async {
        calls++;
        throw const SocketException('Connection refused');
      }));
      await expectLater(client.get(Uri.parse('https://offline.example/')),
          throwsA(isA<SourceException>()));
      expect(calls, 3);
    });

    test('protection SSRF : HTTP, IP, localhost et DNS privé refusés', () async {
      expect(() => EngineHttpClient.checkUrl(Uri.parse('http://site.example/'), const []),
          throwsA(isA<SourceException>()));
      expect(() => EngineHttpClient.checkUrl(Uri.parse('https://127.0.0.1/'), const []),
          throwsA(isA<SourceException>()));
      expect(() => EngineHttpClient.checkUrl(Uri.parse('https://localhost/'), const []),
          throwsA(isA<SourceException>()));
      expect(() => EngineHttpClient.checkUrl(Uri.parse('https://user:pw@site.example/'), const []),
          throwsA(isA<SourceException>()));
      final client = EngineHttpClient(
        client: MockClient((_) async => http.Response('secret', 200)),
        resolver: (_) async => [InternetAddress('10.0.0.5')],
      );
      await expectLater(client.get(Uri.parse('https://intranet.example/')),
          throwsA(isA<SourceException>().having((e) => e.message, 'message',
              contains('réseau privé'))));
    });

    test('requêtes simultanées identiques dédupliquées', () async {
      var calls = 0;
      final client = EngineHttpClient(checkDns: false, client: MockClient((r) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('<html>ok</html>', 200);
      }));
      final uri = Uri.parse('https://site.example/page');
      final results = await Future.wait([client.get(uri), client.get(uri), client.get(uri)]);
      expect(results.every((r) => r.ok), isTrue);
      expect(calls, 1);
    });
  });
}
