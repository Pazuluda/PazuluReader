import '../core/models.dart';
import '../core/source.dart';
import 'availability.dart';
import 'validation/page_validation.dart';

/// Raw page list as published by a source, before validation.
class PageFetch {
  const PageFetch({
    required this.pages,
    this.announcedTotal,
    this.access = AccessKind.open,
    this.transport = 'html',
    this.needsBrowser = false,
    this.policy = ValidationPolicy.strict,
    this.imageHeaders = const {},
    this.accessDetail,
  });

  final List<PageRef> pages;

  /// Total published by the SITE (counter, page selector, reader JSON, API
  /// page count). Null when unknown — never guessed from the image count.
  final int? announcedTotal;
  final AccessKind access;
  final String? accessDetail;

  /// api / html / browser / offline
  final String transport;

  /// Static HTML is insufficient: the hidden WebView2 must render the page.
  final bool needsBrowser;
  final ValidationPolicy policy;

  /// Headers needed to load THESE images (e.g. Referer = chapter URL).
  final Map<String, String> imageHeaders;
}

/// Optional contract for connectors that know more than a URL list
/// (announced total, access state, validation tolerance). Existing
/// [ContentSource] implementations keep working without it.
abstract interface class PageResolvingSource implements ContentSource {
  Future<PageFetch> fetchPages(SourceChapter chapter);
}

/// Optional availability check that does not download pages.
abstract interface class AvailabilitySource implements ContentSource {
  Future<ChapterAvailability> checkAvailability(SourceChapter chapter);
}

/// Connectors whose pages may need the hidden WebView2 renderer.
abstract interface class BrowserRenderedSource implements ContentSource {
  /// Hosts the hidden browser may load for this connector.
  List<String> get browserHosts;
}
