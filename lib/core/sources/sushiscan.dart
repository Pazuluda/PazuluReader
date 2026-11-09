import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;

import '../../engine/availability.dart';
import '../../engine/http/html_extract.dart';
import '../../engine/source_contract.dart';
import '../../engine/validation/access_detector.dart';
import '../../engine/validation/page_validation.dart';
import '../chapter_key.dart';
import '../chapter_pagination.dart';
import '../models.dart';
import '../schedule/site_latest.dart';
import '../source.dart';

/// Native Dart adapter for PUBLIC SushiScan.net HTML. Does not use an APK,
/// an external server, an extension repository or any Java background runtime.
/// No attempts to evade a challenge, login, copyright restriction or paywall.
class SushiScanSource
    implements ContentSource, PageResolvingSource, BrowserRenderedSource {
  SushiScanSource({http.Client? client}) : _client = client ?? http.Client();

  static const root = 'https://sushiscan.net';
  static final Uri _root = Uri.parse(root);
  static final RegExp _entryPattern = RegExp(
      r'^\s*(?:chapitre|chapter|ch\.?|volume|vol\.?)\s*[:#-]?\s*(\d+(?:[.,]\d+)?)\b',
      caseSensitive: false);
  final http.Client _client;

  @override
  String get id => 'sushiscan_net';
  @override
  String get name => 'SushiScan.net · connecteur Pazulu';
  @override
  List<String> get languages => const ['fr'];
  @override
  String get credit => 'Pages : source tierce SushiScan.net. Respecter les droits des auteurs et des éditeurs.';
  @override
  Map<String, String> get imageHeaders => const {
    'Referer': '$root/',
    'User-Agent': 'PazuluReader/0.5 (Windows; client personnel)',
  };

  @override
  List<String> get browserHosts => const ['sushiscan.net'];

  /// Reject redirects/canonical URLs to private networks or off-domain pages.
  static Uri _verified(String raw, {String? base, bool requireSeries = false}) {
    final uri = Uri.parse(base ?? root).resolve(raw.trim());
    if (uri.scheme != 'https' || uri.host.toLowerCase() != _root.host ||
        uri.hasPort || uri.userInfo.isNotEmpty ||
        (requireSeries && !uri.path.startsWith('/catalogue/'))) {
      throw const SourceException('Adresse de fiche non autorisée pour SushiScan.net.');
    }
    return uri;
  }

  Future<dom.Document> _get(String address) async {
    final uri = _verified(address);
    http.Response response;
    try {
      response = await _client.get(uri, headers: const {
        'User-Agent': 'PazuluReader/0.5 (Windows; client personnel)',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'fr-FR,fr;q=0.9',
      }).timeout(const Duration(seconds: 18));
    } on TimeoutException {
      throw const SourceException('SushiScan.net ne répond pas dans les délais.');
    } catch (error) {
      throw SourceException('SushiScan.net inaccessible : $error');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw SourceException('Accès limité par SushiScan.net (HTTP ${response.statusCode}). '
          'Aucun contournement n’est tenté.', statusCode: response.statusCode);
    }
    if (response.request?.url.host != null &&
        response.request!.url.host != _root.host) {
      throw const SourceException('Redirection hors du domaine SushiScan refusée.');
    }
    if (response.statusCode != 200) {
      throw SourceException('SushiScan.net : HTTP ${response.statusCode}.',
          statusCode: response.statusCode);
    }
    if (response.bodyBytes.length > 7 * 1024 * 1024) {
      throw const SourceException('Page HTML anormalement volumineuse.');
    }
    final page = html_parser.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    final title = page.querySelector('title')?.text.toLowerCase() ?? '';
    if (title.contains('just a moment') || title.contains('attention required')) {
      throw const SourceException('Page de protection détectée. Aucun contournement tenté.');
    }
    return page;
  }

  /// Site HTML may expose lazy pages via data-* or srcset, while src itself
  /// points at a blank SVG/GIF. Only read ordinary public HTML attributes.
  static String? _image(dom.Element? node, String base) {
    if (node == null) return null;
    const names = [
      'data-src', 'data-lazy-src', 'data-original', 'data-cfsrc',
      'data-url', 'data-image', 'data-srcset', 'data-lazy-srcset',
      'srcset', 'src',
    ];
    for (final name in names) {
      final value = node.attributes[name]?.trim();
      if (value == null || value.isEmpty) continue;
      final candidates = name.endsWith('srcset')
          ? value.split(',').map((part) => part.trim().split(RegExp(r'\s+')).first)
          : [value];
      for (final candidate in candidates) {
        if (candidate.isEmpty || candidate == '#' ||
            candidate.startsWith('data:') || candidate.startsWith('blob:')) continue;
        final uri = Uri.tryParse(base)?.resolve(candidate);
        if (uri == null || uri.scheme != 'https' || uri.hasPort ||
            uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
        final path = uri.path.toLowerCase();
        if (path.endsWith('.svg') || path.endsWith('.gif') ||
            path.contains('placeholder') || path.contains('readerarea.svg') ||
            path.contains('loading.') || uri.host.endsWith('a-ads.com')) continue;
        return uri.toString();
      }
    }
    return null;
  }

  static String _cleanTitle(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Search parser: parse known card selectors, never turn search result URLs
  /// into a working reader before a chapter/page check succeeds.
  static List<WorkInfo> parseSearch(String raw, {int limit = 30}) {
    final doc = html_parser.parse(raw);
    final out = <String, WorkInfo>{};
    final anchors = doc.querySelectorAll(
        '.page-item-detail .post-title a, .post-title a, '
        '.c-tabs-item__content .post-title a, .bsx a, '
        '.listupd a[href*="/catalogue/"], '
        'a[href*="/catalogue/"]');
    for (final link in anchors) {
      final href = link.attributes['href'];
      if (href == null) continue;
      Uri uri;
      try { uri = _verified(href, requireSeries: true); } catch (_) { continue; }
      final heading = _cleanTitle(link.attributes['title'] ?? link.text);
      if (heading.isEmpty) continue;
      final card = link.parent?.parent;
      final imageNode = card?.querySelector('img') ?? link.querySelector('img');
      final cover = _image(imageNode, root);
      out.putIfAbsent(uri.toString(), () => WorkInfo(
        id: 'sushiscan_net:${uri.toString()}',
        title: heading,
        coverUrl: cover,
        type: ContentType.manhwa,
        languages: const ['fr'],
        longStrip: true,
        links: [SourceLink(sourceId: 'sushiscan_net', workId: uri.toString())],
      ));
      if (out.length >= limit) break;
    }
    return out.values.toList();
  }

  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final address = _root.replace(queryParameters: {'s': q}).toString();
    final document = await _get(address);
    return parseSearch(document.outerHtml, limit: limit);
  }

  /// Series page may use an H1 and og:image even when card metadata is sparse.
  static WorkInfo parseWork(String raw, String workId) {
    final uri = _verified(workId, requireSeries: true);
    final page = html_parser.parse(raw);
    final title = _cleanTitle(
      page.querySelector('.post-title h1, .entry-title, h1')?.text ??
      page.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '');
    if (title.isEmpty) throw const SourceException('Titre absent de la fiche SushiScan.net.');
    final desc = _cleanTitle(page.querySelector('.description-summary, .summary__content, .post-content_item .summary-content')?.text ?? '');
    final cover = _image(page.querySelector('.summary_image img, .tab-summary img'), root) ??
        page.querySelector('meta[property="og:image"]')?.attributes['content'];
    return WorkInfo(
      id: 'sushiscan_net:${uri.toString()}',
      title: title,
      description: desc,
      coverUrl: cover,
      type: ContentType.manhwa,
      languages: const ['fr'],
      longStrip: true,
      links: [SourceLink(sourceId: 'sushiscan_net', workId: uri.toString())],
    );
  }

  @override
  Future<WorkInfo> getWork(String workId) async {
    final uri = _verified(workId, requireSeries: true);
    return parseWork((await _get(uri.toString())).outerHtml, uri.toString());
  }

  /// Resolve a user-pasted chapter/volume URL to its canonical series page.
  /// No guessing of a series ID from the URL slug: the site's own "back to
  /// series" link must exist. Only metadata is fetched here.
  Future<WorkInfo> seriesFromChapterUrl(String chapterUrl) async {
    final uri = _verified(chapterUrl);
    if (uri.path.startsWith('/catalogue/')) return getWork(uri.toString());
    final doc = await _get(uri.toString());
    final seriesLinks = doc.querySelectorAll('a[href*="/catalogue/"]');
    for (final link in seriesLinks) {
      final href = link.attributes['href'];
      if (href == null) continue;
      try {
        final series = _verified(href, requireSeries: true);
        return await getWork(series.toString());
      } catch (e) {
        if (e is SourceException && !e.message.contains('autorisée')) rethrow;
      }
    }
    throw const SourceException('Cette page ne contient pas de lien fiable '
        'vers la fiche série SushiScan.net.');
  }

  /// Volumes remain separate canonical keys from chapters. This is essential
  /// for pages like Solo Leveling with Vol 1..15 then Ch 179.5..200.
  static List<SourceChapter> parseChapters(String raw, String workId) {
    _verified(workId, requireSeries: true);
    final page = html_parser.parse(raw);
    final out = <String, SourceChapter>{};
    final selectors = <String>[
      '.listing-chapters_wrap li a', '.wp-manga-chapter a',
      '.eplister li a', '.chapters-list a', '.chapter-list a',
      '.main .listing-chapters_wrap a',
    ];
    var anchors = page.querySelectorAll(selectors.join(', '));
    // Some custom WP themes use a flat list without the Madara selectors.
    if (anchors.isEmpty) anchors = page.querySelectorAll('a[href]');
    for (final a in anchors) {
      final title = _cleanTitle(a.text);
      final match = _entryPattern.firstMatch(title);
      if (match == null) continue;
      final rawHref = a.attributes['href'];
      if (rawHref == null) continue;
      Uri url;
      try { url = _verified(rawHref); } catch (_) { continue; }
      final value = match.group(1)!.replaceAll(',', '.');
      final isVolume = RegExp(r'^(?:volume|vol\.?)', caseSensitive: false)
          .hasMatch(title);
      final key = ChapterKey.parse(isVolume ? 'volume-$value' : value);
      // Release date written next to the chapter (« janvier 16, 2026 »,
      // « 2 jours ») — inside the link on MangaThemesia, beside it on Madara.
      DateTime? published;
      dom.Element? row = a;
      while (row != null && row.localName != 'li') {
        row = row.parent;
      }
      final dateNode = (row ?? a).querySelector(
          '.chapterdate, .chapter-release-date, .chapter-date, .epl-date, .date, time');
      final dateText = dateNode?.attributes['datetime'] ?? dateNode?.text;
      if (dateText != null) {
        final when = ReleaseTimeParser.parse(dateText);
        if (when != null && !when.$1.isAfter(DateTime.now())) published = when.$1;
      }
      out.putIfAbsent(url.toString(), () => SourceChapter(
        sourceId: 'sushiscan_net',
        chapterId: url.toString(),
        key: key,
        lang: 'fr',
        group: 'SushiScan.net',
        title: isVolume ? 'Volume $value' : 'Chapitre $value',
        volume: isVolume ? value : null,
        publishedAt: published,
      ));
    }
    return out.values.toList();
  }

  @override
  Future<List<SourceChapter>> listChapters(String workId, {
    required List<String> langs,
  }) async {
    if (!langs.contains('fr')) return [];
    final uri = _verified(workId, requireSeries: true);
    return parseChapters((await _get(uri.toString())).outerHtml, uri.toString());
  }

  @override
  Future<List<SourceChapter>> latestChapters(String workId, {
    required List<String> langs, int limit = 30,
  }) async {
    final chapters = await listChapters(workId, langs: langs);
    chapters.sort((a, b) => b.key.compareTo(a.key));
    return chapters.take(limit).toList();
  }

  /// Only user-invoked chapter pages are requested. Never render image links
  /// from unscoped HTML or advertising frames as a chapter.
  static List<PageRef> parsePages(String raw, String chapterUrl) {
    final base = _verified(chapterUrl).toString();
    // MangaThemesia reader: every page is listed in ts_reader.run({...})
    // while #readerarea stays empty until JavaScript runs. This is the
    // site's own page list, read from the public HTML — no request forged.
    final ts = HtmlExtract.tsReader(raw);
    if (ts != null && ts.primary.isNotEmpty) {
      final baseUri = Uri.parse(base);
      final fromJson = <String, PageRef>{};
      for (final candidate in ts.primary) {
        final url = HtmlExtract.resolveImage(candidate, baseUri);
        if (url == null || Uri.parse(url).host.endsWith('a-ads.com')) continue;
        fromJson.putIfAbsent(url, () => PageRef(url));
        if (fromJson.length >= 300) break;
      }
      if (fromJson.isNotEmpty) return fromJson.values.toList();
    }
    final doc = html_parser.parse(raw);
    // Only search inside reader containers. Headings, ads, covers and cards
    // outside these containers are not chapter images.
    final images = doc.querySelectorAll(
        '.reading-content img, .reading-content picture source, '
        '#readerarea img, #readerarea picture source, '
        '.reader-area img, .reader-area picture source, '
        '.chapter-content img, .chapter-images img, '
        '.wp-manga-chapter-img, .page-break img, '
        '.reading-content noscript img, #readerarea noscript img');
    final out = <String, PageRef>{};
    for (final img in images) {
      final url = _image(img, base);
      if (url == null) continue;
      final uri = Uri.parse(url);
      if (uri.path.toLowerCase().endsWith('.svg') ||
          uri.host.endsWith('a-ads.com')) continue;
      out.putIfAbsent(url, () => PageRef(url));
      if (out.length >= 300) break;
    }
    return out.values.toList();
  }

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async {
    if (chapter.sourceId != id || chapter.isExternal) {
      throw const SourceException('Chapitre incompatible avec SushiScan.net.');
    }
    final uri = _verified(chapter.chapterId);
    final document = await _get(uri.toString());
    final pages = parsePages(document.outerHtml, uri.toString());
    final total = ChapterPagination.totalFromHtml(document);
    if (total != null && pages.length < total) {
      throw SourceException('Chapitre pagine : ${pages.length}/$total images dans le HTML. '
          'Analyse du navigateur necessaire avant toute validation.');
    }
    if (pages.length == 1 && total == null) {
      // This static HTML cannot prove whether the JS reader offers more pages.
      // Caller must inspect the rendered chapter before committing progress.
      throw const SourceException('Une seule image HTML : verification du lecteur rendu necessaire.');
    }
    if (pages.isEmpty) {
      throw const SourceException('Aucune image lisible dans le HTML public. '
        'Le site a pu changer ou limiter la lecture ; aucune protection n’est contournée.');
    }
    return pages;
  }

  /// Engine 2.0 contract: page list + the total announced by the site +
  /// access state. The reader decides between native display and the hidden
  /// WebView2 renderer from this, never from a guess.
  @override
  Future<PageFetch> fetchPages(SourceChapter chapter) async {
    if (chapter.sourceId != id || chapter.isExternal) {
      throw const SourceException('Chapitre incompatible avec SushiScan.net.');
    }
    final uri = _verified(chapter.chapterId);
    final document = await _get(uri.toString());
    final raw = document.outerHtml;
    if (HtmlExtract.looksProtected(raw)) {
      throw const SourceException('Lecteur protégé (images chiffrées) : '
          'Pazulu ne contourne pas cette protection.');
    }
    final pages = parsePages(raw, uri.toString());
    final ts = HtmlExtract.tsReader(raw);
    final fromJson = ts != null && ts.primary.isNotEmpty;
    final htmlTotal = ChapterPagination.totalFromHtml(document);
    int? announced = fromJson ? pages.length : htmlTotal;
    if (htmlTotal != null && announced != null && htmlTotal > announced) {
      announced = htmlTotal;
    }
    final text = AccessDetector.visibleTextOf(raw);
    final access = AccessDetector.classifyText(text, imageCount: pages.length);
    if (access.isRestriction && pages.length < 2) {
      throw ChapterRestrictedException('SushiScan.net : ${access.label}.', kind: access);
    }
    final needsBrowser = pages.isEmpty ||
        (announced != null && pages.length < announced) ||
        (pages.length == 1 && announced == null);
    return PageFetch(
      pages: pages,
      announcedTotal: announced,
      access: access,
      transport: needsBrowser ? 'browser' : (fromJson ? 'html-json' : 'html'),
      needsBrowser: needsBrowser,
      policy: const ValidationPolicy(minWidth: 300, minHeight: 40,
          verticalStrip: true, allowSmallPages: 2),
      imageHeaders: {...imageHeaders, 'Referer': uri.toString()},
    );
  }
}
