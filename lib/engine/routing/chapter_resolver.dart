import '../../core/models.dart';
import '../../core/source.dart';
import '../availability.dart';
import '../diagnostics/engine_log.dart';
import '../http/engine_http.dart';
import '../source_contract.dart';
import '../validation/page_validation.dart';

/// Raised when the hidden WebView2 must render the chapter. The reader owns
/// the WebView; the engine only says so.
class NeedsBrowserRendering implements Exception {
  const NeedsBrowserRendering(this.chapter, {this.fetch});
  final SourceChapter chapter;
  final PageFetch? fetch;
  @override
  String toString() => 'Rendu navigateur nécessaire pour ${chapter.chapterId}';
}

typedef ImageProbe = Future<PageProbe> Function(int index, String url,
    Map<String, String> headers, CancelToken? cancel);

/// Turns "a source said these are the pages" into a validated
/// [ChapterPages]: metadata ≠ availability ≠ readable pages.
class ChapterResolver {
  ChapterResolver({
    required this.http,
    required this.log,
    this.validator = const PageValidationEngine(),
    ImageProbe? probe,
    this.probeBytes = 48 * 1024,
  }) {
    _probe = probe ?? _httpProbe;
  }

  final EngineHttpClient http;
  final EngineLog log;
  final PageValidationEngine validator;
  final int probeBytes;
  late final ImageProbe _probe;

  Future<PageProbe> _httpProbe(int index, String url, Map<String, String> headers,
      CancelToken? cancel) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5',
        ...headers,
      }, truncateAt: probeBytes, timeout: const Duration(seconds: 12),
          anyPublicHost: true, retries: 0, cancel: cancel);
      return PageProbe.fromBytes(index, url, response.status, response.bytes,
          contentType: response.contentType, finalHost: response.finalUri.host,
          complete: !response.truncated);
    } on RequestCancelled {
      rethrow;
    } catch (e) {
      return PageProbe(index: index, url: url, error: '$e');
    }
  }

  /// Fetches the page list from [source] and validates it. Throws
  /// [ChapterRestrictedException] for paywalls/age gates/etc.,
  /// [NeedsBrowserRendering] when static HTML is insufficient, and returns
  /// a [ChapterPages] (possibly not readable) otherwise.
  Future<ChapterPages> resolve(SourceChapter chapter, ContentSource source, {
    CancelToken? cancel,
    bool probe = true,
  }) async {
    final watch = Stopwatch()..start();
    PageFetch fetch;
    if (source is PageResolvingSource) {
      fetch = await source.fetchPages(chapter);
    } else {
      final pages = await source.getPages(chapter);
      fetch = PageFetch(
        pages: pages,
        announcedTotal: chapter.pages > 0 ? chapter.pages : null,
        transport: 'api',
        imageHeaders: source.imageHeaders,
      );
    }
    if (cancel?.isCancelled ?? false) throw const RequestCancelled();
    if (fetch.needsBrowser) throw NeedsBrowserRendering(chapter, fetch: fetch);
    final result = await validate(fetch, chapter: chapter,
        extraHeaders: source.imageHeaders, cancel: cancel, probe: probe,
        started: watch);
    log.info('chapter_resolved', sourceId: chapter.sourceId,
        message: '${chapter.key.id} ${chapter.lang}: ${result.summary}',
        elapsed: watch.elapsed,
        data: {'transport': result.transport, 'completeness': result.completeness.name});
    return result;
  }

  /// Validates an already obtained page list (HTML, API or WebView2).
  Future<ChapterPages> validate(PageFetch fetch, {
    required SourceChapter chapter,
    Map<String, String> extraHeaders = const {},
    CancelToken? cancel,
    bool probe = true,
    Stopwatch? started,
  }) async {
    final watch = started ?? (Stopwatch()..start());
    final pages = fetch.pages;
    final announced = fetch.announcedTotal ?? (chapter.pages > 0 ? chapter.pages : null);
    final structural = validator.structural(pages, announcedTotal: announced,
        policy: fetch.policy);
    final probes = <PageProbe>[];
    final headers = {...extraHeaders, ...fetch.imageHeaders};
    if (probe && !structural.any((i) => i.fatal && i.pageIndex == null)) {
      final sample = PageValidationEngine.probeSample(pages.length);
      probes.addAll(await Future.wait([
        for (final i in sample) _probe(i, pages[i].url, headers, cancel),
      ]));
    }
    return validator.evaluate(pages,
        announcedTotal: announced,
        probes: probes,
        policy: fetch.policy,
        transport: fetch.transport,
        elapsed: watch.elapsed,
        imageHeaders: headers);
  }
}
