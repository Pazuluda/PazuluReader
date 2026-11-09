import 'dart:convert';

import 'source_catalog.dart';
import 'source_extensions.dart';

/// Normalized output from an embedded browser, not an API scraper.
class PageInspection {
  const PageInspection({required this.pageUrl, required this.title, required this.pages});

  final String pageUrl;
  final String title;
  final List<String> pages;

  /// Browser APIs may return either a Dart map, a JSON string, or a JSON
  /// string containing another JSON string, depending on the platform.
  static PageInspection fromBrowser(Object raw, CatalogSite site, {SourceRecipe? recipe}) {
    dynamic value = raw;
    for (var i = 0; i < 3 && value is String; i++) {
      value = jsonDecode(value);
    }
    if (value is! Map || value['url'] is! String || value['images'] is! List) {
      throw const FormatException('La page ne contient pas de chapitre reconnu.');
    }
    final url = value['url'] as String;
    if (!(recipe?.accepts(site, url) ?? site.accepts(url))) {
      throw const FormatException('La page a change de domaine : analyse refusee.');
    }
    final seen = <String>{};
    final pages = <String>[];
    for (final src in value['images'] as List) {
      if (src is! String || src.length > 2500) continue;
      final uri = Uri.tryParse(src);
      if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
          uri.host.isEmpty || uri.hasPort || isLocalAddress(uri.host)) continue;
      if (seen.add(uri.toString())) pages.add(uri.toString());
      if (pages.length >= 300) break;
    }
    if (pages.length < 2) {
      throw const FormatException('Pas assez de pages detectees pour ouvrir le lecteur.');
    }
    return PageInspection(
      pageUrl: url,
      title: (value['title'] is String ? value['title'] as String : site.title).trim(),
      pages: pages,
    );
  }

  static bool isLocalAddress(String host) {
    final h = host.toLowerCase();
    // Direct IP addresses and local hosts are never valid chapter image hosts.
    return h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') ||
        h.contains(':') || RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(h);
  }
}

/// The same JavaScript extractor is used for every site, with adjustable CSS
/// selectors only. Does NOT fetch URLs, bypass login/paywall or inspect network
/// requests; it examines images already present in the visible page DOM.
String makeInspectionScript(SourceRecipe recipe) {
  if (!recipe.canInspect) throw const FormatException('Inspection desactivee pour cette source.');
  final selectors = jsonEncode(recipe.selectors);
  final minWidth = recipe.minimumWidth;
  final minHeight = recipe.minimumHeight;
  return '''
(() => {
  const selectors = $selectors;
  const pageImages = [];
  const all = [];
  const visited = new Set();
  for (const selector of selectors) {
    try {
      for (const img of document.querySelectorAll(selector)) {
        if (img.tagName === 'IMG' && !visited.has(img)) {
          all.push(img); visited.add(img);
        }
      }
    } catch (_) {}
  }
  // The generic fallback must NOT turn cover images from a homepage or
  // catalogue into a fake readable chapter. Only try on likely chapter URLs.
  const looksLikeChapter = /(?:chapter|chapitre|episode|ch[-_]|ep[-_])/i
    .test(location.pathname);
  if (all.length < 2 && looksLikeChapter) {
    for (const img of document.images) {
      if (!visited.has(img)) { all.push(img); visited.add(img); }
    }
  }
  for (const img of all) {
    const rect = img.getBoundingClientRect();
    const w = img.naturalWidth || img.width || rect.width;
    const h = img.naturalHeight || img.height || rect.height;
    if (w > 0 && h > 0 && (w < $minWidth || h < $minHeight)) continue;
    const src = img.getAttribute('data-src') ||
      img.getAttribute('data-original') || img.getAttribute('data-lazy-src') ||
      img.getAttribute('data-url') || img.currentSrc || img.getAttribute('src');
    if (!src) continue;
    try {
      const url = new URL(src, document.baseURI);
      if (url.protocol !== 'https:') continue;
      if (/logo|avatar|icon|banner|advert/i.test(url.pathname)) continue;
      pageImages.push(url.href);
    } catch (_) {}
  }
  return JSON.stringify({url: location.href, title: document.title,
    images: Array.from(new Set(pageImages)).slice(0, 300)});
})()
''';
}
