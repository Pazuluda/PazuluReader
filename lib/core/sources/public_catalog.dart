import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../engine/availability.dart';
import '../../engine/http/engine_http.dart';
import '../../engine/http/html_extract.dart';
import '../../engine/identity/canonical_chapter.dart';
import '../../engine/identity/listing_guard.dart';
import '../../engine/source_contract.dart';
import '../../engine/validation/access_detector.dart';
import '../../engine/validation/page_validation.dart';
import '../chapter_identity.dart';
import '../chapter_key.dart';
import '../chapter_listing.dart';
import '../chapter_pagination.dart';
import '../log.dart';
import '../models.dart';
import '../schedule/site_latest.dart';
import '../site_index.dart';
import '../source.dart';
import '../source_catalog.dart';
import '../source_health.dart';

/// Universal connector for every site of the directory (Engine 2.0).
///
/// Auto-detects the usual reader families (Madara, MangaThemesia/ts_reader,
/// generic readers): search, work page, chapter list, latest works AND pages.
/// Pages always go through the Page Validation Engine; when static HTML is
/// not enough the hidden WebView2 renders the chapter. Domain moves are
/// followed (public DNS only) and remembered. No login, paywall, CAPTCHA or
/// image protection is ever bypassed: such pages are reported, not read.
class PublicCatalogSource
    implements ContentSource, PageResolvingSource, BrowserRenderedSource {
  PublicCatalogSource(this.site, {this.fetchHtml, EngineHttpClient? http})
      : _http = http;

  final CatalogSite site;

  /// Dependency injection for isolated fixture tests.
  final Future<String> Function(Uri)? fetchHtml;
  EngineHttpClient? _http;
  EngineHttpClient get http => _http ??= EngineHttpClient();

  /// Host the site redirected to (domain change), learned at runtime.
  String? movedHost;

  /// Saves the HTML of a page the reader could not handle (chapter drawn in
  /// JavaScript, absurd chapter numbers) for diagnosis. Set by the app.
  static void Function(String sourceId, String kind, String url, String body)? onDiagnosticPage;

  /// Status written on the work pages read (« OnGoing », « Completed »,
  /// « Hiatus », « Dropped »…), by work address. Input of the status engine.
  final Map<String, String> statusLabels = {};

  /// « Status : OnGoing » / « Statut En cours » on a Madara / MangaThemesia
  /// work page (tags removed), or null.
  static String? statusOnPage(String body) {
    final value = RegExp(
        r'^[\s:]*(on ?going|completed?|finished|ended|hiatus|on hold|dropped|'
        r'cancell?ed|axed|en cours|termin[ée]e?|en pause|abandonn[ée]e?|annul[ée]e?|'
        r'releasing|publishing)(?![a-z])',
        caseSensitive: false);
    var tries = 0;
    for (final m in RegExp(r'\b(?:status|statut)\b', caseSensitive: false).allMatches(body)) {
      if (++tries > 40) break;
      final end = (m.end + 400).clamp(0, body.length);
      final text = body.substring(m.end, end)
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      final v = value.firstMatch(text);
      if (v != null) return v.group(1);
    }
    return null;
  }

  @override
  String get id => 'public_${site.id}';
  @override
  String get name => site.title;
  @override
  List<String> get languages => site.languages;
  @override
  Map<String, String> get imageHeaders => {'Referer': _base.toString()};
  @override
  String get credit => 'Pages : ${site.title}. Respectez les droits des auteurs et des éditeurs.';
  @override
  List<String> get browserHosts => _hosts;

  String get _rootHost {
    final h = Uri.parse(site.home).host.toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  List<String> get _hosts => [_rootHost, if (movedHost != null) movedHost!];

  Uri get _base => movedHost == null
      ? Uri.parse(site.home)
      : Uri(scheme: 'https', host: movedHost, path: '/');

  bool accepts(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty || u.hasPort ||
        u.host.isEmpty) {
      return false;
    }
    return EngineHttpClient.hostAllowed(u.host, _hosts);
  }

  Future<(String, Uri)> _fetch(Uri uri, {bool cache = true, String method = 'GET',
      Map<String, String> headers = const {}, String? body}) async {
    final injected = fetchHtml;
    if (injected != null) return (await injected(uri), uri);
    final response = await http.get(uri,
        allowedHosts: _hosts,
        anyPublicHost: true,
        cache: cache,
        method: method,
        body: body,
        sourceId: id,
        timeout: const Duration(seconds: 12),
        maxBytes: 3 * 1024 * 1024,
        headers: {'Accept': 'text/html,application/xhtml+xml', ...headers});
    final finalHost = response.finalUri.host.toLowerCase();
    if (!EngineHttpClient.hostAllowed(finalHost, _hosts)) {
      // The site moved: keep following it under its new domain.
      movedHost = finalHost.startsWith('www.') ? finalHost.substring(4) : finalHost;
    }
    if (!response.ok) {
      final kind = AccessDetector.classifyStatus(response.status);
      throw ChapterRestrictedException('${site.title} : HTTP ${response.status} '
          '(${kind.label}).', kind: kind, statusCode: response.status);
    }
    final text = response.text;
    final title = RegExp(r'<title[^>]*>([^<]{0,200})', caseSensitive: false)
        .firstMatch(text)?.group(1)?.toLowerCase() ?? '';
    if (title.contains('just a moment') || title.contains('attention required') ||
        title.contains('access denied')) {
      throw ChapterRestrictedException('${site.title} demande une vérification '
          'anti-robot : aucun contournement.', kind: AccessKind.botChallenge);
    }
    return (text, response.finalUri);
  }

  ContentType get _defaultType => ContentType.other;

  // ------------------------------------------------------------------ search

  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async {
    final q = query.trim();
    if (q.length < 2) return [];
    // Madara search first, then the plain WordPress / MangaThemesia form.
    final first = _base.replace(path: '/', queryParameters: {'s': q, 'post_type': 'wp-manga'});
    final (body, finalUri) = await _fetch(first);
    var found = parsePublicSearchHtml(body, site: site, sourceId: id, query: q,
        limit: limit, accepts: accepts, base: finalUri);
    if (found.isEmpty) {
      final (body2, final2) = await _fetch(_base.replace(path: '/', queryParameters: {'s': q}));
      found = parsePublicSearchHtml(body2, site: site, sourceId: id, query: q,
          limit: limit, accepts: accepts, base: final2);
    }
    return found;
  }

  /// Works shown on the site's home page (latest updates / popular).
  /// Metadata only: titles, links and cover URLs, never chapter pages.
  /// Chapters of the site's « latest updates » block, with their time.
  Future<List<SiteRelease>> latestReleases({int limit = 60}) async {
    final (body, finalUri) = await _fetch(_base);
    return SiteLatestParser.parse(body, finalUri, limit: limit);
  }

  Future<List<WorkInfo>> browseLatest({int limit = 40}) async {
    final (body, finalUri) = await _fetch(_base);
    return parseCatalogCards(body, sourceId: id, site: site, accepts: accepts,
        base: finalUri, limit: limit);
  }

  /// Reads a JSON chapter list (MangaNato family), page after page. The
  /// format is read generically: every object with a chapter number /
  /// name and a slug or address becomes a chapter, with its date when one
  /// of its fields holds one.
  Future<List<SourceChapter>> _chaptersFromJsonApi(String apiUrl, String comicSlug,
      String? template, Uri page, String lang) async {
    final out = <String, SourceChapter>{};
    var offset = 0;
    for (var round = 0; round < 40; round++) {
      final base = Uri.parse(apiUrl);
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        'limit': '100',
        'offset': '$offset',
      });
      final (body, _) = await _fetch(uri, cache: false,
          headers: {'Accept': 'application/json', 'Referer': page.toString(),
              'X-Requested-With': 'XMLHttpRequest'});
      final before = out.length;
      void visit(Object? node) {
        if (node is List) {
          for (final x in node) {
            visit(x);
          }
          return;
        }
        if (node is! Map) return;
        String? field(List<String> names) {
          for (final n in names) {
            final v = node[n];
            if (v is String && v.trim().isNotEmpty) return v.trim();
            if (v is num) return '$v';
          }
          return null;
        }
        final slug = field(const ['chapter_slug', 'slug', 'chapterSlug']);
        final url = field(const ['url', 'link', 'href']);
        final name = field(const ['chapter_name', 'name', 'title', 'chapter_title']);
        final number = field(const ['chapter_num', 'chapter_number', 'number', 'num', 'chapter']);
        if ((slug != null || url != null) && (name != null || number != null)) {
          var address = url;
          if (address == null && slug != null) {
            address = template != null
                ? template.replaceAll('__MANGA__', comicSlug).replaceAll('__CHAPTER__', slug)
                : page.resolve('${page.path.endsWith('/') ? '' : '${page.path}/'}$slug').toString();
          }
          final resolved = page.resolve(address!).toString();
          var (key, volume) = ChapterLabelParser.parse(name ?? 'Chapter $number');
          if (key.number == null && number != null) key = ChapterKey.parse(number);
          final dateText = field(const ['updated_at', 'created_at', 'date', 'time',
              'uploaded_at', 'published_at', 'release_date']);
          DateTime? when;
          if (dateText != null) {
            when = DateTime.tryParse(dateText)?.toLocal() ?? ReleaseTimeParser.parse(dateText)?.$1;
          }
          if (key.number != null && accepts(resolved) &&
              (when == null || !when.isAfter(DateTime.now().add(const Duration(hours: 12))))) {
            out.putIfAbsent(resolved, () => SourceChapter(
                sourceId: id, chapterId: resolved, key: key, lang: lang, group: site.title,
                title: name ?? key.longLabel, volume: volume, publishedAt: when));
          }
          return;
        }
        for (final v in node.values) {
          visit(v);
        }
      }
      visit(jsonDecode(body));
      final added = out.length - before;
      if (added == 0 || added < 100) break;
      offset += added;
    }
    return out.values.toList();
  }

  // --------------------------------------------------------------- catalogue

  /// The site's whole list of series (titles + addresses), for the local
  /// index. Metadata only, a few requests per site:
  /// 1. WordPress API of Madara sites (100 series per request);
  /// 2. « list-mode » page of MangaThemesia sites (everything on one page);
  /// 3. the site map (addresses only, titles rebuilt from them).
  /// Any anti-robot / login page stops here: nothing is bypassed.
  /// Why the last catalogue reading failed (journal of the start-up).
  String? catalogueFailure;

  Future<List<IndexedTitle>> catalogueTitles({int maxPages = 60}) async {
    catalogueFailure = null;
    final errors = <String>[];
    void note(String method, Object e) {
      final text = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      errors.add('$method: ${text.length > 90 ? text.substring(0, 90) : text}');
    }
    final out = <String, IndexedTitle>{};
    void add(String? title, String? href, {bool fromSlug = false}) {
      if (href == null) return;
      var url = href.trim();
      if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
      final resolved = _base.resolve(url).toString();
      if (!accepts(resolved)) return;
      final t = HtmlExtract.cleanText(title);
      if (t.length < 2) return;
      out.putIfAbsent(resolved, () => IndexedTitle(t, resolved, fromSlug: fromSlug));
    }

    // 1. Madara: WordPress REST API.
    try {
      for (var page = 1; page <= maxPages; page++) {
        final (body, _) = await _fetch(
            _base.replace(path: '/wp-json/wp/v2/wp-manga', queryParameters: {
              'per_page': '100', 'page': '$page', '_fields': 'link,title',
            }),
            cache: false, headers: const {'Accept': 'application/json'});
        final data = jsonDecode(body);
        if (data is! List || data.isEmpty) break;
        for (final item in data) {
          if (item is! Map) continue;
          final rendered = item['title'] is Map ? '${(item['title'] as Map)['rendered']}' : '';
          add(html.parseFragment(rendered).text, '${item['link']}');
        }
        if (data.length < 100) break;
      }
    } catch (e) {
      // Not a Madara site, API closed, or end of the pages.
      if (out.isEmpty) note('API WordPress', e);
    }
    if (out.length >= 10) return out.values.toList();

    // 1b. Madara: the « load more » list of the theme (the method used by
    // the site's own archive page), 500 series per request.
    try {
      for (var page = 0; page < 20; page++) {
        final before = out.length;
        final (body, finalUri) = await _fetch(_base.replace(path: '/wp-admin/admin-ajax.php'),
            method: 'POST', cache: false,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body: 'action=madara_load_more&page=$page'
                '&template=madara-core%2Fcontent%2Fcontent-archive'
                '&vars%5Bpost_type%5D=wp-manga&vars%5Bpost_status%5D=publish'
                '&vars%5Borderby%5D=post_title&vars%5Border%5D=ASC'
                '&vars%5Bposts_per_page%5D=500&vars%5Bpaged%5D=1');
        final doc = html.parse(body);
        for (final a in doc.querySelectorAll('.post-title a, h3.h5 a, .item-summary a, h3 a')) {
          final href = a.attributes['href'];
          if (href != null) add(a.text, finalUri.resolve(href).toString());
        }
        if (out.length == before) break;
      }
    } catch (e) {
      if (out.isEmpty) note('liste Madara', e);
    }
    if (out.length >= 10) return out.values.toList();

    // 2. MangaThemesia: one page with every series.
    for (final path in const ['/manga/list-mode/', '/series/list-mode/', '/comics/list-mode/']) {
      try {
        final (body, finalUri) = await _fetch(_base.replace(path: path), cache: false);
        final doc = html.parse(body);
        for (final a in doc.querySelectorAll('.soralist a.series, .soralist li a, .blix a')) {
          final href = a.attributes['href'];
          if (href == null) continue;
          add(a.text, finalUri.resolve(href).toString());
        }
        if (out.length >= 10) return out.values.toList();
      } catch (e) {
        // Try the next address.
        if (path == '/manga/list-mode/') note('list-mode', e);
      }
    }

    // 2b. « A-Z » / « manga list » pages: links to /manga/<slug>/ pages.
    for (final path in const ['/manga-list/', '/az-list/', '/manga/', '/series/', '/comics/']) {
      try {
        final (body, finalUri) = await _fetch(_base.replace(path: path), cache: false);
        final doc = html.parse(body);
        for (final a in doc.querySelectorAll('a[href]')) {
          final target = finalUri.resolve(a.attributes['href']!.trim());
          final seg = target.pathSegments.where((p) => p.isNotEmpty).toList();
          if (seg.length != 2 ||
              !const {'manga', 'series', 'comics', 'webtoon', 'manhwa', 'serie', 'oeuvre'}
                  .contains(seg.first.toLowerCase()) ||
              RegExp(r'^(page|feed|genre|tag|list|category)$').hasMatch(seg.last)) {
            continue;
          }
          final text = HtmlExtract.spacedText(a);
          add(text.length >= 2 ? text : IndexedTitle.titleFromSlug(seg.last), target.toString(),
              fromSlug: text.length < 2);
        }
        if (out.length >= 30) return out.values.toList();
      } catch (e) {
        if (path == '/manga-list/') note('liste A-Z', e);
      }
    }

    // 3. Site maps (WordPress core, Yoast / Rank Math).
    final maps = <Uri>[];
    try {
      final (index, _) = await _fetch(_base.replace(path: '/wp-sitemap.xml'), cache: false,
          headers: const {'Accept': 'application/xml,text/xml'});
      for (final m in RegExp(r'<loc>\s*([^<\s]+)\s*</loc>').allMatches(index)) {
        final u = m.group(1)!;
        if (RegExp(r'manga|series|comic|webtoon|manhwa', caseSensitive: false).hasMatch(u)) {
          maps.add(Uri.parse(u.replaceFirst('http://', 'https://')));
        }
      }
    } catch (_) {}
    if (maps.isEmpty) {
      for (final path in const ['/sitemap_index.xml', '/sitemap.xml']) {
        try {
          final (index, _) = await _fetch(_base.replace(path: path), cache: false,
              headers: const {'Accept': 'application/xml,text/xml'});
          for (final m in RegExp(r'<loc>\s*([^<\s]+)\s*</loc>').allMatches(index)) {
            final u = m.group(1)!;
            if (u.endsWith('.xml') &&
                RegExp(r'manga|series|comic|webtoon|manhwa', caseSensitive: false).hasMatch(u)) {
              maps.add(Uri.parse(u.replaceFirst('http://', 'https://')));
            }
          }
          if (maps.isNotEmpty) break;
        } catch (_) {}
      }
    }
    if (maps.isEmpty) errors.add('plan du site : absent');
    for (final map in maps.take(20)) {
      if (!accepts(map.toString())) continue;
      try {
        final (body, _) = await _fetch(map, cache: false,
            headers: const {'Accept': 'application/xml,text/xml'});
        for (final m in RegExp(r'<loc>\s*([^<\s]+)\s*</loc>').allMatches(body)) {
          final u = Uri.tryParse(m.group(1)!);
          if (u == null) continue;
          final segments = u.pathSegments.where((p) => p.isNotEmpty).toList();
          // A series page (/manga/slug/), never a chapter or an image.
          if (segments.length != 2 ||
              RegExp(r'chap|episode|\.(jpe?g|png|webp)$', caseSensitive: false)
                  .hasMatch(segments.last)) {
            continue;
          }
          add(IndexedTitle.titleFromSlug(segments.last), u.toString(), fromSlug: true);
        }
      } catch (e) {
        note('plan du site', e);
      }
    }
    if (out.isEmpty) catalogueFailure = errors.isEmpty ? 'aucune série trouvée' : errors.join(' · ');
    return out.values.toList();
  }

  // -------------------------------------------------------------------- work

  @override
  Future<WorkInfo> getWork(String workId) async {
    if (!accepts(workId)) {
      throw const SourceException('URL de fiche hors du site sélectionné.');
    }
    final (body, finalUri) = await _fetch(Uri.parse(workId));
    final doc = html.parse(body);
    // The page heading is more faithful than og:title ("… - Site Name").
    final title = doc.querySelector('.post-title h1, h1.entry-title, .seriestucon h1, '
            '.series-title h1, h1')?.text ??
        doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        doc.querySelector('title')?.text ?? site.title;
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ??
        doc.querySelector('.summary__content, .entry-content[itemprop=description], '
            '.description-summary')?.text ?? '';
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
        HtmlExtract.imageUrlOf(doc.querySelector('.summary_image img, .thumb img'), finalUri);
    return WorkInfo(id: '$id:$workId', title: HtmlExtract.cleanText(title),
        description: HtmlExtract.cleanText(desc), coverUrl: cover,
        type: _defaultType, languages: site.languages,
        links: [SourceLink(sourceId: id, workId: workId)]);
  }

  // ---------------------------------------------------------------- chapters

  static const _chapterItems = [
    'li.wp-manga-chapter', '#chapterlist li', '.eplister li', '.chapter-list li',
    '.chapters li', 'ul.row-content-chapter li', '.list-chapter li',
    '.chapter-item', '.chapters-list li', '#chapter-list li',
  ];

  @override
  Future<List<SourceChapter>> listChapters(String workId, {
    required List<String> langs,
  }) async {
    if (!accepts(workId)) throw const SourceException('Fiche hors domaine.');
    final lang = langs.where(site.languages.contains).firstOrNull;
    if (lang == null) return [];
    final requested = Uri.parse(workId);
    final (body, finalUri) = await _fetch(requested, cache: false);
    // The site redirected elsewhere (home page, another series): its
    // chapters are NOT this work's chapters.
    if (!ListingGuard.samePage(requested, finalUri)) {
      throw SourceException('${site.title} : fiche introuvable (redirection vers '
          '${finalUri.path.isEmpty ? '/' : finalUri.path}).');
    }
    final status = statusOnPage(body);
    if (status != null) statusLabels[workId] = status;
    var chapters = parseChapterList(body, finalUri, lang: lang);
    if (chapters.isEmpty && body.contains('wp-manga')) {
      // Recent Madara themes load the list with POST {work}/ajax/chapters/.
      final path = finalUri.path.endsWith('/') ? finalUri.path : '${finalUri.path}/';
      try {
        final (ajax, _) = await _fetch(
            Uri(scheme: 'https', host: finalUri.host, path: '${path}ajax/chapters/'),
            method: 'POST', cache: false,
            headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': finalUri.toString()});
        chapters = parseChapterList(ajax, finalUri, lang: lang);
      } on SourceException {
        // Reported below through the generic listing fallback.
      }
    }
    // Sites of the MangaNato family (manganato, mangabats, mangakakalot…)
    // load the whole list (with dates) from a JSON address written in the
    // page: data-api-url=".../api/manga/__SLUG__/chapters".
    final api = RegExp(r'data-api-url="([^"]+__SLUG__[^"]*)"').firstMatch(body);
    final comicSlug = RegExp(r'data-comic-slug="([^"]+)"').firstMatch(body)?.group(1);
    final template = RegExp(r'data-chapter-url-template="([^"]+)"').firstMatch(body)?.group(1);
    if (api != null && comicSlug != null) {
      try {
        final fromApi = await _chaptersFromJsonApi(api.group(1)!.replaceAll('__SLUG__', comicSlug),
            comicSlug, template, finalUri, lang);
        if (fromApi.length > chapters.length) chapters = fromApi;
      } catch (e) {
        AppLog.info('${site.title} : liste JSON des chapitres illisible ($e)');
      }
    }
    if (chapters.isEmpty) {
      try {
        final generic = ChapterListingParser.parseListing(body, site: site,
            pageUrl: Uri.parse(site.home).resolve(finalUri.path).toString());
        chapters = [
          for (final c in generic)
            SourceChapter(sourceId: id, chapterId: c.url, key: c.key, lang: lang,
                group: site.title, title: c.key.longLabel),
        ];
      } catch (_) {
        // Nothing reliable on this page: an empty list, not a guess.
      }
    }
    // Only chapters whose URL belongs to THIS work page, and never a list
    // whose numbers mix several series (home-page "latest updates").
    // (the address actually served: a series may have moved, see samePage)
    final owned = ListingGuard.belongingTo(finalUri.toString(), chapters);
    // Absurd numbers (« 24828 » in a 250-chapter series): page kept so that
    // the exact way this site writes its chapters can be read.
    final numbers = [for (final c in owned) if (c.key.number != null) c.key.number!]..sort();
    if (numbers.length >= 5 && numbers.last > 2000 &&
        numbers.last > numbers.length * 5) {
      onDiagnosticPage?.call(id, 'liste', workId, body);
    }
    // The newest chapters have no date while older ones do (mangaread
    // 317–319): page kept to read how this site writes « new » chapters.
    if (owned.length >= 10) {
      final sorted = [...owned.where((c) => c.key.number != null)]
        ..sort((a, b) => b.key.number!.compareTo(a.key.number!));
      if (sorted.length >= 10 && sorted.first.publishedAt == null &&
          sorted.skip(5).take(5).every((c) => c.publishedAt != null)) {
        onDiagnosticPage?.call(id, 'liste-sans-date', workId, body);
      }
    }
    // Only 1–3 chapters (mangabats / manganato « 2 ch. » for 280): the rest
    // of the list is loaded some other way — page kept to add it.
    if (owned.isNotEmpty && owned.length <= 3) {
      onDiagnosticPage?.call(id, 'liste-courte', workId, body);
    }
    if (ListingGuard.looksMixed(owned)) {
      throw SourceException('${site.title} : liste de chapitres incohérente '
          '(plusieurs œuvres mélangées), ignorée.');
    }
    // One stray link far above the list (another series): removed, the
    // rest of the list is kept.
    return ListingGuard.withoutStrays(owned);
  }

  List<SourceChapter> parseChapterList(String body, Uri base, {required String lang}) {
    final doc = html.parse(body);
    final out = <String, SourceChapter>{};
    for (final selector in _chapterItems) {
      for (final item in doc.querySelectorAll(selector)) {
        final a = item.localName == 'a' ? item : item.querySelector('a[href]');
        final href = a?.attributes['href'];
        if (a == null || href == null) continue;
        final url = base.resolve(href.trim());
        if (!accepts(url.toString()) || url.path == base.path) continue;
        // Listed but NOT released: premium / VIP / early access / « coming
        // soon » chapters. Counting them would announce a FR release that
        // does not exist yet (only the EN chapter is out).
        if (isLockedChapterItem(item)) continue;
        final named = item.querySelector('.chapternum, .chapter-name, .chapter-title, .epl-num');
        final label = HtmlExtract.spacedText(named ?? a);
        var (key, volume) = ChapterLabelParser.parse(label);
        if (key.number == null && !_isNamedSpecial(key.id)) {
          final fromUrl = ChapterIdentity.detect(title: label, url: url.toString());
          if (fromUrl == null) continue;
          key = fromUrl;
        }
        // Release date shown next to the chapter (Madara, MangaThemesia…).
        final dated = item.querySelector('.chapter-release-date a[title]');
        final dateText = dated?.attributes['title'] ??
            item.querySelector('.chapter-release-date, .chapterdate, .chapter-time, '
                '.dt, time')?.text;
        final when = dateText == null ? null : ReleaseTimeParser.parse(dateText);
        // A release date in the future: announced, not released.
        if (when != null && when.$1.isAfter(DateTime.now().add(const Duration(hours: 12)))) continue;
        out.putIfAbsent(url.toString(), () => SourceChapter(
              sourceId: id,
              chapterId: url.toString(),
              key: key,
              lang: lang,
              group: site.title,
              title: label.isEmpty ? key.longLabel : label,
              volume: volume,
              publishedAt: when?.$1,
            ));
      }
      if (out.isNotEmpty) break; // first matching family wins
    }
    return out.values.toList();
  }

  static const _lockClasses = {
    'premium', 'premium-block', 'locked', 'lock', 'is-locked', 'chapter-lock', 'vip',
    'paid', 'coin', 'coins', 'fa-lock', 'fa-coins', 'coming-soon', 'early-access',
    'scheduled', 'unreleased', 'chapter-locked', 'bi-lock', 'bi-lock-fill',
  };
  static final _lockText = RegExp(
      r'(?<![a-z])(premium|vip|coming soon|bientôt disponible|bientot disponible|early access|'
      r'accès anticipé|acces anticipe|unlock|débloquer|debloquer|free in|gratuit dans|'
      r'disponible dans|disponible le|locked|verrouillé|payant)(?![a-zà-ÿ])',
      caseSensitive: false);

  /// A chapter entry marked as locked / premium / not yet released.
  static bool isLockedChapterItem(dom.Element item) {
    bool lockedClass(dom.Element e) =>
        e.classes.any((c) => _lockClasses.contains(c.toLowerCase()));
    if (lockedClass(item)) return true;
    for (final e in item.querySelectorAll('*')) {
      if (lockedClass(e)) return true;
    }
    return _lockText.hasMatch(item.text);
  }

  static bool _isNamedSpecial(String id) => RegExp(
          r'^(?:volume-|extra|bonus|special|omake|side-story|hors-serie|prologue|epilogue|oneshot)')
      .hasMatch(id);

  @override
  Future<List<SourceChapter>> latestChapters(String workId, {
    required List<String> langs, int limit = 30,
  }) async {
    final chapters = await listChapters(workId, langs: langs);
    chapters.sort((a, b) => b.key.compareTo(a.key));
    return chapters.take(limit).toList();
  }

  // ------------------------------------------------------------------- pages

  static const _readerSelectors = [
    '.reading-content .page-break img', '.reading-content img', '.reading-content picture',
    'img.wp-manga-chapter-img', '#readerarea img', '#readerarea picture',
    '.rdminimal img', '.chapter-content img', '.chapter-images img',
    '.reader-area img', '.container-chapter-reader img', '#chapter-reader img',
    '.chapter-reader img', '.reader-content img', '#chapter-content img',
    '.page-chapter img', '.vung-doc img', '.chapter-container img',
  ];

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async {
    final fetch = await fetchPages(chapter);
    if (fetch.needsBrowser) {
      throw SourceException('${site.title} : rendu JavaScript nécessaire pour ce chapitre.');
    }
    return fetch.pages;
  }

  @override
  Future<PageFetch> fetchPages(SourceChapter chapter) async {
    if (chapter.sourceId != id) {
      throw const SourceException('Chapitre incompatible avec ce site.');
    }
    final address = chapter.isExternal ? chapter.externalUrl! : chapter.chapterId;
    if (!accepts(address)) throw const SourceException('Chapitre hors domaine.');
    final (body, finalUri) = await _fetch(Uri.parse(address), cache: false);
    return parsePageFetch(body, finalUri);
  }

  PageFetch parsePageFetch(String raw, Uri chapterUrl) {
    if (HtmlExtract.looksProtected(raw)) {
      throw SourceException('${site.title} protège ses images (lecteur chiffré) : '
          'aucun contournement.');
    }
    final doc = html.parse(raw);
    var images = <String>[];
    int? announced;
    var transport = 'html';
    final ts = HtmlExtract.tsReader(raw);
    if (ts != null && ts.primary.isNotEmpty) {
      images = [
        for (final u in ts.primary)
          if (HtmlExtract.resolveImage(u, chapterUrl) case final String ok) ok,
      ];
      announced = images.length;
      transport = 'html-json';
    }
    if (images.isEmpty) {
      final pre = HtmlExtract.madaraPreloaded(raw);
      if (pre != null && pre.isNotEmpty) {
        images = [
          for (final u in pre)
            if (HtmlExtract.resolveImage(u, chapterUrl) case final String ok) ok,
        ];
        announced = images.length;
        transport = 'html-json';
      }
    }
    if (images.isEmpty) images = HtmlExtract.readerImages(doc, _readerSelectors, chapterUrl);
    final counter = ChapterPagination.totalFromHtml(doc);
    if (counter != null && (announced == null || counter > announced)) announced = counter;
    if (images.length < 2 || (announced != null && images.length < announced)) {
      // Pages drawn by JavaScript: their addresses are usually already in
      // the page's scripts. Read there by OUR reader (no browser).
      final embedded = HtmlExtract.embeddedImages(raw, chapterUrl);
      if (embedded.length > images.length) {
        images = embedded;
        transport = 'html-script';
      }
    }
    // Images found only in scripts are not proof of a chapter: the page's
    // own text decides (paywall, login, anti-robot).
    final access = AccessDetector.classifyText(AccessDetector.visibleTextOf(raw),
        // (at most 5: a cookie bar stays harmless, a paywall text still wins)
        imageCount: transport == 'html-script' && images.length > 5 ? 5 : images.length);
    // Images found only in scripts on a paywall / login / anti-robot page
    // are previews or decoys, never the chapter.
    if (access.isRestriction &&
        (images.length < 2 ||
            (transport == 'html-script' &&
                (access == AccessKind.subscriptionRequired ||
                    access == AccessKind.loginRequired ||
                    access == AccessKind.botChallenge)))) {
      throw ChapterRestrictedException('${site.title} : ${access.label}.', kind: access);
    }
    final needsBrowser = images.isEmpty ||
        (announced != null && images.length < announced) ||
        (images.length == 1 && announced == null);
    if (needsBrowser) {
      // Kept so that an exact reader can be written for this site.
      PublicCatalogSource.onDiagnosticPage?.call(id, 'chapitre', chapterUrl.toString(), raw);
    }
    return PageFetch(
      pages: [for (final u in images) PageRef(u)],
      announcedTotal: announced,
      access: access,
      transport: needsBrowser ? 'browser' : transport,
      needsBrowser: needsBrowser,
      policy: const ValidationPolicy(minWidth: 300, minHeight: 40,
          verticalStrip: true, allowSmallPages: 2),
      imageHeaders: {'Referer': chapterUrl.toString()},
    );
  }
}

String _simplify(String value) => value.toLowerCase()
  .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

bool _looksLikeChapterPath(String path) =>
    RegExp(r'/chapter[-/]|/chapitre[-/]|/episode[-/]|-chapter-\d|-chapitre-\d',
        caseSensitive: false).hasMatch(path);

/// Strict, reusable Madara/WordPress search-result parser. Reject unrelated
/// navigation links even when a homepage contains the search words.
List<WorkInfo> parsePublicSearchHtml(String document, {
  required CatalogSite site,
  required String sourceId,
  required String query,
  int limit = 30,
  bool Function(String url)? accepts,
  Uri? base,
}) {
  final doc = html.parse(document);
  final titleText = doc.querySelector('title')?.text.toLowerCase() ?? '';
  if (titleText.contains('just a moment') ||
      titleText.contains('access denied') ||
      titleText.contains('checking your browser')) {
    throw const SourceException('La recherche est bloquée par le site.');
  }
  final qTerms = _simplify(query).split(' ').where((v) => v.length > 1).toList();
  if (qTerms.isEmpty) return [];
  final root = base ?? Uri.parse(site.home);
  final allowed = accepts ?? site.accepts;
  final found = <String, WorkInfo>{};
  // Only search-card contexts, not any link from site navigation.
  for (final card in doc.querySelectorAll(
    '.page-item-detail, .c-tabs-item__content, .post-item, '
    '.manga-item, .item-summary, .series-item, .listupd .bs, .bsx, '
    '.search-result, article')) {
    if (found.length >= limit.clamp(1, 50)) break;
    final a = card.querySelector(
      '.post-title a[href], .entry-title a[href], '
      '.tt a[href], h3 a[href], h4 a[href], '
      'a[href*="/manga/"], a[href*="/series/"], a[href*="/comics/"], a[href]');
    if (a == null) continue;
    final href = a.attributes['href'];
    if (href == null) continue;
    final target = root.resolve(href);
    if (!allowed(target.toString())) continue;
    if (_looksLikeChapterPath(target.path)) continue;
    final titleNode = card.querySelector('.tt, .post-title, h3, h4');
    final title = (a.attributes['title'] ?? titleNode?.text ?? a.text)
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    final normalized = _simplify(title);
    if (title.length < 3 || !qTerms.every(normalized.contains)) continue;
    // The link must be the card's series, not a neighbouring link.
    if (!ListingGuard.slugAgreesWithTitle(target.toString(), title)) continue;
    final cover = HtmlExtract.imageUrlOf(card.querySelector('img'), root);
    final url = target.toString().split('#').first;
    found.putIfAbsent(url, () => WorkInfo(
      id: '$sourceId:$url', title: title, coverUrl: cover,
      description: card.querySelector('.summary-content, .excerpt, .description')
        ?.text.trim() ?? '',
      type: ContentType.other, languages: site.languages,
      links: [SourceLink(sourceId: sourceId, workId: url)],
    ));
  }
  return found.values.toList();
}

/// Home-page / catalogue cards (latest updates, popular) of the usual
/// families. Metadata only.
List<WorkInfo> parseCatalogCards(String document, {
  required String sourceId,
  required CatalogSite site,
  required bool Function(String url) accepts,
  required Uri base,
  int limit = 40,
}) {
  final doc = html.parse(document);
  final found = <String, WorkInfo>{};
  for (final card in doc.querySelectorAll(
      '.page-item-detail, .c-tabs-item__content, .listupd .bs, .listupd .utao, '
      '.listupd .uta, .bsx, .manga-item, .series-item, .item-summary, '
      '.post-item, .manga-card, .comic-item')) {
    if (found.length >= limit) break;
    dom.Element? link;
    for (final a in card.querySelectorAll('a[href]')) {
      final target = base.resolve(a.attributes['href']!.trim());
      if (accepts(target.toString()) && !_looksLikeChapterPath(target.path) &&
          target.path.length > 1) {
        link = a;
        break;
      }
    }
    if (link == null) continue;
    final target = base.resolve(link.attributes['href']!.trim());
    final titleNode = card.querySelector('.tt, .post-title, .series-title, h3, h4, .title');
    final title = HtmlExtract.cleanText(link.attributes['title'] ?? titleNode?.text ?? link.text);
    if (title.length < 2 || title.length > 160) continue;
    if (!ListingGuard.slugAgreesWithTitle(target.toString(), title)) continue;
    final url = target.removeFragment().toString();
    found.putIfAbsent(url, () => WorkInfo(
          id: '$sourceId:$url',
          title: title,
          coverUrl: HtmlExtract.imageUrlOf(card.querySelector('img'), base),
          type: ContentType.other,
          languages: site.languages,
          links: [SourceLink(sourceId: sourceId, workId: url)],
        ));
  }
  return found.values.toList();
}

/// Limited public HTML request (kept for the saved-link listing checks).
/// Redirects, private IPs, oversized bodies and non-HTML responses are denied.
Future<String> fetchBoundedPublicHtml(Uri url, {required CatalogSite site}) async {
  if (!site.accepts(url.toString())) {
    throw const SourceException('Hôte non autorisé.');
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'PazuluReader/2.0 (public metadata search)';
  try {
    final addresses = await InternetAddress.lookup(url.host)
      .timeout(const Duration(seconds: 5));
    if (addresses.isEmpty || addresses.any(isNonPublicIpAddress)) {
      throw const SourceException('Hôte non public.');
    }
    final request = await client.getUrl(url).timeout(const Duration(seconds: 6));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw SourceException('Accès limité (HTTP ${response.statusCode}).');
    }
    if (response.statusCode != 200) {
      throw SourceException('Recherche impossible (HTTP ${response.statusCode}).');
    }
    final content = response.headers.contentType?.mimeType;
    if (content != 'text/html' && content != 'application/xhtml+xml') {
      throw const SourceException('Réponse non HTML.');
    }
    final chunks = BytesBuilder(copy: false);
    await for (final part in response.timeout(const Duration(seconds: 8))) {
      if (chunks.length + part.length > 1024 * 1024) {
        throw const SourceException('Page HTML trop volumineuse.');
      }
      chunks.add(part);
    }
    return utf8.decode(chunks.takeBytes(), allowMalformed: true);
  } on TimeoutException {
    throw const SourceException('Délai de réponse dépassé.');
  } finally {
    client.close(force: true);
  }
}
