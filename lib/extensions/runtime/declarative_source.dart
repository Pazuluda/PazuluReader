import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/chapter_pagination.dart';
import '../../core/models.dart';
import '../../core/source.dart';
import '../../engine/availability.dart';
import '../../engine/http/engine_http.dart';
import '../../engine/http/html_extract.dart';
import '../../engine/identity/canonical_chapter.dart';
import '../../engine/source_contract.dart';
import '../../engine/validation/access_detector.dart';
import '../../engine/validation/page_validation.dart';
import '../manifest.dart';

/// Level-1 extension: a [ContentSource] driven only by a validated manifest.
/// All requests go through [EngineHttpClient] (host allow-list, SSRF guard,
/// rate limits, 429 handling). No script from the site is executed here.
class DeclarativeHtmlSource
    implements ContentSource, PageResolvingSource, BrowserRenderedSource {
  DeclarativeHtmlSource(this.manifest, this.http) {
    for (final host in manifest.hosts) {
      http.configureHost(host,
          maxConcurrent: manifest.maxConcurrent,
          requestsPerMinute: manifest.requestsPerMinute);
    }
  }

  final ExtensionManifest manifest;
  final EngineHttpClient http;

  HtmlRules get rules => manifest.html ?? const HtmlRules();
  Uri get _home => Uri.parse(manifest.home);

  @override
  String get id => manifest.id;
  @override
  String get name => manifest.name;
  @override
  List<String> get languages => manifest.languages;
  @override
  String get credit => 'Pages : ${manifest.name} (${manifest.hosts.first}). '
      'Respectez les droits des auteurs et des éditeurs.';
  @override
  Map<String, String> get imageHeaders => manifest.imageMode == 'referer'
      ? {'Referer': _home.toString()}
      : const {};
  @override
  List<String> get browserHosts => manifest.hosts;

  bool get _browserCapable => manifest.transport == ExtensionTransport.browser;

  ContentType get _type => switch (manifest.contentTypes.first) {
        'manga' => ContentType.manga,
        'manhwa' => ContentType.manhwa,
        'manhua' => ContentType.manhua,
        'webtoon' => ContentType.webtoon,
        'novel' || 'webnovel' => ContentType.novel,
        _ => ContentType.other,
      };

  bool get _vertical => manifest.paginationMode == 'vertical' ||
      manifest.readingDirection == 'vertical' ||
      (manifest.paginationMode == 'auto' &&
          manifest.contentTypes.every((t) => t == 'manhwa' || t == 'webtoon' || t == 'manhua'));

  Uri _verified(String raw, {Uri? base}) {
    final uri = (base ?? _home).resolve(raw.trim());
    return EngineHttpClient.checkUrl(uri, manifest.hosts);
  }

  Future<(dom.Document, String)> _fetchDoc(Uri uri, {bool cache = true}) async {
    final response = await http.get(uri, allowedHosts: manifest.hosts, cache: cache,
        sourceId: id, headers: const {'Accept': 'text/html,application/xhtml+xml'});
    final text = response.text;
    if (!response.ok) {
      final kind = AccessDetector.classifyStatus(response.status);
      throw ChapterRestrictedException(
          '${manifest.name} : HTTP ${response.status} (${kind.label}).',
          kind: kind, statusCode: response.status);
    }
    return (html_parser.parse(text), text);
  }

  // ---------------------------------------------------------------- search

  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async {
    if (!manifest.capabilities.search) return const [];
    final q = query.trim();
    if (q.length < 2) return const [];
    final template = rules.searchUrl;
    if (template == null) return const [];
    final encoded = Uri.encodeQueryComponent(q);
    final address = template.replaceAll('{query}', encoded);
    final uri = address.startsWith('http') ? _verified(address) : _verified(address, base: _home);
    final (doc, raw) = await _fetchDoc(uri);
    final results = parseSearch(doc, limit: limit);
    if (results.isEmpty) {
      final access = AccessDetector.classifyText(AccessDetector.visibleTextOf(raw));
      if (access == AccessKind.botChallenge) {
        throw ChapterRestrictedException('${manifest.name} demande une vérification '
            'anti-robot. Aucun contournement n\'est tenté.', kind: access);
      }
    }
    return results;
  }

  List<WorkInfo> parseSearch(dom.Document doc, {int limit = 30}) {
    final out = <String, WorkInfo>{};
    final items = rules.searchItem == null
        ? [doc.documentElement ?? dom.Element.tag('html')]
        : _select(doc, rules.searchItem!);
    for (final item in items) {
      final links = rules.searchLink == null
          ? [item]
          : (item.localName == 'a' ? [item] : _selectIn(item, rules.searchLink!));
      for (final link in links) {
        final href = link.attributes['href'];
        if (href == null) continue;
        Uri uri;
        try {
          uri = _verified(href);
        } catch (_) {
          continue;
        }
        final prefix = rules.seriesPathPrefix;
        if (prefix != null && prefix != '/' && !uri.path.startsWith(prefix)) continue;
        if (_looksLikeChapterUrl(uri)) continue;
        final titleNode = rules.searchTitle == null ? null : _firstIn(item, rules.searchTitle!);
        final title = HtmlExtract.cleanText(link.attributes['title'] ??
            titleNode?.text ?? link.text);
        if (title.isEmpty) continue;
        final coverNode = rules.searchCover == null ? null : _firstIn(item, rules.searchCover!);
        final cover = HtmlExtract.imageUrlOf(coverNode, _home);
        final key = uri.removeFragment().toString();
        out.putIfAbsent(key, () => WorkInfo(
              id: '$id:$key',
              title: title,
              coverUrl: cover,
              type: _type,
              languages: manifest.languages,
              longStrip: _vertical,
              links: [SourceLink(sourceId: id, workId: key)],
            ));
        break; // one work per result card
      }
      if (out.length >= limit) break;
    }
    return out.values.toList();
  }

  bool _looksLikeChapterUrl(Uri uri) {
    final pattern = rules.chapterPathPattern;
    if (pattern != null) return RegExp(pattern).hasMatch(uri.path);
    return RegExp(r'(?:chapitre|chapter|episode)[-_/]?\d', caseSensitive: false)
        .hasMatch(uri.path);
  }

  // ------------------------------------------------------------------ work

  @override
  Future<WorkInfo> getWork(String workId) async {
    final uri = _verified(workId);
    final (doc, _) = await _fetchDoc(uri);
    return parseWork(doc, uri);
  }

  WorkInfo parseWork(dom.Document doc, Uri uri) {
    final title = HtmlExtract.cleanText(
        (rules.workTitle == null ? null : _first(doc, rules.workTitle!))?.text ??
            doc.querySelector('meta[property="og:title"]')?.attributes['content']);
    if (title.isEmpty) {
      throw SourceException('Titre absent de la fiche ${manifest.name}.');
    }
    final description = HtmlExtract.cleanText(
        (rules.workDescription == null ? null : _first(doc, rules.workDescription!))?.text);
    final cover = HtmlExtract.imageUrlOf(
            rules.workCover == null ? null : _first(doc, rules.workCover!), uri) ??
        doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    final key = uri.removeFragment().toString();
    return WorkInfo(
      id: '$id:$key',
      title: title,
      description: description,
      coverUrl: cover,
      type: _type,
      languages: manifest.languages,
      longStrip: _vertical,
      links: [SourceLink(sourceId: id, workId: key)],
    );
  }

  // -------------------------------------------------------------- chapters

  @override
  Future<List<SourceChapter>> listChapters(String workId, {
    required List<String> langs,
  }) async {
    if (!manifest.capabilities.chapters) return const [];
    if (!manifest.languages.any(langs.contains)) return const [];
    final uri = _verified(workId);
    final (doc, raw) = await _fetchDoc(uri);
    var chapters = parseChapters(doc, uri);
    if (chapters.isEmpty && rules.family == 'madara') {
      // Recent Madara themes load the list with POST {work}/ajax/chapters/.
      final ajax = _verified('${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}ajax/chapters/',
          base: uri);
      try {
        final response = await http.get(ajax, method: 'POST', allowedHosts: manifest.hosts,
            sourceId: id, headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': uri.toString(),
            });
        if (response.ok) chapters = parseChapters(html_parser.parse(response.text), uri);
      } on SourceException {
        // Reported below as "no chapter" with the access diagnosis.
      }
    }
    if (chapters.isEmpty) {
      final access = AccessDetector.classifyText(AccessDetector.visibleTextOf(raw));
      if (access.isRestriction) {
        throw ChapterRestrictedException('${manifest.name} : ${access.label}.', kind: access);
      }
    }
    final wanted = manifest.languages.firstWhere(langs.contains,
        orElse: () => manifest.languages.first);
    return [
      for (final c in chapters)
        SourceChapter(sourceId: c.sourceId, chapterId: c.chapterId, key: c.key,
            lang: wanted, group: c.group, title: c.title, volume: c.volume,
            publishedAt: c.publishedAt),
    ];
  }

  List<SourceChapter> parseChapters(dom.Document doc, Uri base) {
    final out = <String, SourceChapter>{};
    final itemSelector = rules.chapterItem;
    if (itemSelector == null) return const [];
    final pattern = rules.chapterPathPattern == null ? null : RegExp(rules.chapterPathPattern!);
    for (final item in _select(doc, itemSelector)) {
      final link = item.localName == 'a'
          ? item
          : (rules.chapterLink == null ? null : _firstIn(item, rules.chapterLink!));
      final href = link?.attributes['href'];
      if (link == null || href == null) continue;
      Uri url;
      try {
        url = _verified(href, base: base);
      } catch (_) {
        continue;
      }
      if (pattern != null && !pattern.hasMatch(url.path)) continue;
      if (url.path == base.path) continue;
      final titleNode = rules.chapterTitle == null ? null : _firstIn(item, rules.chapterTitle!);
      final label = HtmlExtract.cleanText(titleNode?.text ?? link.text);
      if (label.isEmpty) continue;
      final (key, volume) = ChapterLabelParser.parse(label);
      if (key.id == label.toLowerCase() && key.number == null &&
          !RegExp(r'one.?shot', caseSensitive: false).hasMatch(label)) {
        continue; // navigation link, not a chapter
      }
      final volNode = rules.chapterVolume == null ? null : _firstIn(item, rules.chapterVolume!);
      out.putIfAbsent(url.toString(), () => SourceChapter(
            sourceId: id,
            chapterId: url.toString(),
            key: key,
            lang: manifest.languages.first,
            group: manifest.name,
            title: label,
            volume: volume ?? (volNode == null ? null : HtmlExtract.cleanText(volNode.text)),
          ));
    }
    return out.values.toList();
  }

  @override
  Future<List<SourceChapter>> latestChapters(String workId, {
    required List<String> langs, int limit = 30,
  }) async {
    final chapters = await listChapters(workId, langs: langs);
    chapters.sort((a, b) => b.key.compareTo(a.key));
    return chapters.take(limit).toList();
  }

  // ----------------------------------------------------------------- pages

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async {
    final fetch = await fetchPages(chapter);
    if (fetch.needsBrowser) {
      throw SourceException('${manifest.name} : rendu JavaScript nécessaire.');
    }
    return fetch.pages;
  }

  @override
  Future<PageFetch> fetchPages(SourceChapter chapter) async {
    if (chapter.sourceId != id || chapter.isExternal) {
      throw SourceException('Chapitre incompatible avec ${manifest.name}.');
    }
    final uri = _verified(chapter.chapterId);
    final (doc, raw) = await _fetchDoc(uri, cache: false);
    return parsePageFetch(doc, raw, uri);
  }

  PageFetch parsePageFetch(dom.Document doc, String raw, Uri chapterUrl) {
    if (HtmlExtract.looksProtected(raw)) {
      throw SourceException('${manifest.name} protège ce lecteur (images chiffrées). '
          'Pazulu ne contourne pas cette protection.');
    }
    var images = <String>[];
    int? announced;
    var transport = 'html';
    if (rules.useTsReader) {
      final ts = HtmlExtract.tsReader(raw);
      if (ts != null && ts.primary.isNotEmpty) {
        images = [
          for (final u in ts.primary)
            if (HtmlExtract.resolveImage(u, chapterUrl) case final String ok) ok,
        ];
        // The reader JSON is the site's own complete page list.
        announced = images.length;
        transport = 'html-json';
      }
    }
    if (images.isEmpty && rules.useMadaraPreloaded) {
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
    if (images.isEmpty) {
      images = HtmlExtract.readerImages(doc, rules.pageImages, chapterUrl);
    }
    final counter = ChapterPagination.totalFromHtml(doc) ?? _counterTotal(doc);
    if (counter != null && (announced == null || counter > announced)) announced = counter;

    final text = AccessDetector.visibleTextOf(raw);
    var access = AccessDetector.classifyText(text, imageCount: images.length);
    final lower = text.toLowerCase();
    if (access == AccessKind.open && images.length < 6 &&
        rules.restrictedTexts.any((t) => t.isNotEmpty && lower.contains(t.toLowerCase()))) {
      access = AccessKind.subscriptionRequired;
    }
    if (access.isRestriction && images.length < 2) {
      throw ChapterRestrictedException('${manifest.name} : ${access.label}.', kind: access);
    }
    final pagedButSingle = images.length == 1 && (announced ?? 0) > 1;
    final needsBrowser = _browserCapable && (images.isEmpty || pagedButSingle);
    if (images.isEmpty && !needsBrowser) {
      throw SourceException('${manifest.name} : aucune image de chapitre dans le HTML public.');
    }
    return PageFetch(
      pages: [for (final u in images) PageRef(u)],
      announcedTotal: announced,
      access: access,
      transport: needsBrowser ? 'browser' : transport,
      needsBrowser: needsBrowser,
      policy: ValidationPolicy(
        minWidth: _vertical ? 300 : 200,
        minHeight: _vertical ? 40 : 200,
        verticalStrip: _vertical,
        allowSmallPages: _vertical ? 2 : 1,
        allowedImageHosts: const [],
      ),
      imageHeaders: manifest.imageMode == 'referer'
          ? {'Referer': chapterUrl.toString()}
          : const {},
    );
  }

  int? _counterTotal(dom.Document doc) {
    final selector = rules.pageCounter;
    if (selector == null) return null;
    final node = _first(doc, selector);
    if (node == null) return null;
    final m = RegExp(r'\b\d{1,3}\s*/\s*(\d{1,3})\b').firstMatch(node.text);
    final n = m == null ? null : int.tryParse(m.group(1)!);
    return n != null && n > 1 && n <= 400 ? n : null;
  }

  // -------------------------------------------------------------- helpers

  static List<dom.Element> _select(dom.Document doc, String selector) {
    try {
      return doc.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static List<dom.Element> _selectIn(dom.Element el, String selector) {
    try {
      return el.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static dom.Element? _first(dom.Document doc, String selector) {
    try {
      return doc.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  static dom.Element? _firstIn(dom.Element el, String selector) {
    try {
      return el.querySelector(selector);
    } catch (_) {
      return null;
    }
  }
}
