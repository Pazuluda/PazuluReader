import 'dart:convert';

import 'models.dart';

/// Reads image URLs already visible in a browser's DOM after JS rendering.
/// No requests, network interception, DRM workaround or script injection into
/// the site's own logic. The reader triggers this automatically when the chapter is opened.
const visiblePagesScript = r'''
(() => {
  const selectors = [
    '.reading-content img', '.reading-content picture source',
    '#readerarea img', '#readerarea picture source',
    '.reader-area img', '.chapter-content img',
    '.chapter-images img', '.page-break img',
    '.chapter-reader img', '.reader-content img',
    '#chapter-content img', '#chapter-reader img',
    'img.wp-manga-chapter-img'
  ];
  const visited = new Set();
  const images = [];
  const attrs = ['data-src', 'data-lazy-src', 'data-original',
    'data-url', 'data-srcset', 'srcset', 'src'];
  for (const selector of selectors) {
    for (const node of document.querySelectorAll(selector)) {
      if (visited.has(node)) continue;
      visited.add(node);
      let url = '';
      const rendered = node.currentSrc || '';
      if (rendered) {
        try {
          const candidate = new URL(rendered, document.baseURI);
          if (candidate.protocol === 'https:' &&
              !/\.svg$|\.gif$|placeholder|readerarea\.svg|loading\./i.test(candidate.pathname)) {
            url = candidate.href;
          }
        } catch (_) {}
      }
      for (const attr of attrs) {
        if (url) break;
        let v = node.getAttribute(attr) || '';
        if (!v.trim()) continue;
        if (attr.endsWith('srcset')) v = v.trim().split(',')[0].trim().split(/\s+/)[0];
        if (!v || v.startsWith('data:') || v.startsWith('blob:')) continue;
        try {
          const u = new URL(v, document.baseURI);
          if (u.protocol !== 'https:') continue;
          if (/\.svg$|\.gif$|placeholder|readerarea\.svg|loading\./i.test(u.pathname)) continue;
          url = u.href;
          break;
        } catch (_) {}
      }
      if (url) images.push(url);
    }
  }
  // Page-by-page readers expose one image at a time. Detect their page
  // selector instead of declaring the chapter complete after one <img>.
  let announcedTotal = null;
  const counters = document.querySelectorAll(
    '.page-number, .page-numbers, .pagination, .page-select, ' +
    '#pageSelection, #page-select, .reader-pagination');
  for (const node of counters) {
    // Do not treat the concatenated option labels of a select as one counter.
    if (node.tagName === 'SELECT' || node.querySelector?.('select')) continue;
    const label = (node.textContent || '').trim().slice(0, 120);
    const counter = label.match(/\b(\d{1,3})\s*\/\s*(\d{1,3})\b/);
    if (counter) {
      const total = Number(counter[2]);
      if (total >= 2 && total <= 300) announcedTotal = Math.max(announcedTotal || 0, total);
    }
  }
  const controls = [...document.querySelectorAll('select')];
  let candidate = null;
  controls.forEach((select, selectIndex) => {
    const options = [...select.options];
    if (options.length < 2 || options.length > 300) return;
    const numbers = options.map(option => {
      const label = (option.textContent || '').trim();
      const match = label.match(/^(?:page\s*)?(\d+)(?:\s*\/\s*\d+)?$/i);
      return match ? Number(match[1]) : null;
    });
    if (numbers.some(n => n === null) || new Set(numbers).size !== options.length ||
        !numbers.includes(1) || !numbers.includes(options.length) ||
        numbers.some(n => n < 1 || n > options.length)) return;
    const descriptor = (`${select.id} ${select.name} ${select.className} ` +
      `${select.parentElement?.className || ''}`).toLowerCase();
    const named = /page|pagination|reader/.test(descriptor);
    const matchingCounter = announcedTotal === options.length;
    if (!named && !matchingCounter) return;
    const score = (named ? 3 : 0) + (matchingCounter ? 6 : 0);
    if (!candidate || score > candidate.score) {
      candidate = {score, selectIndex, total: options.length,
        current: numbers[select.selectedIndex] || 1};
    }
  });
  const pagination = candidate ? {
    total: candidate.total, current: candidate.current,
    selectIndex: candidate.selectIndex,
  } : {total: announcedTotal, current: 1, selectIndex: null};
  return JSON.stringify({url: location.href,
    images: [...new Set(images)].slice(0, 300), pagination});
})()
''';

class VisibleReaderPages {
  /// Reject private/local image URLs and off-chapter script results. We trust
  /// neither browser page text nor JS return values as executable content.
  static List<PageRef> parse(Object raw, {required String chapterUrl}) {
    dynamic decoded = raw;
    for (var i = 0; i < 3 && decoded is String; i++) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map || decoded['url'] is! String || decoded['images'] is! List) {
      throw const FormatException('Aucune image exploitable dans le DOM rendu.');
    }
    final current = Uri.tryParse(decoded['url'] as String);
    final expected = Uri.tryParse(chapterUrl);
    if (current == null || expected == null || current.scheme != 'https' ||
        current.host != expected.host || current.path != expected.path ||
        current.hasPort || current.userInfo.isNotEmpty) {
      throw const FormatException('La page inspectée ne correspond pas au chapitre.');
    }
    final seen = <String>{};
    final pages = <PageRef>[];
    for (final item in decoded['images'] as List) {
      if (item is! String || item.length > 2500) continue;
      final uri = Uri.tryParse(item);
      if (uri == null || uri.scheme != 'https' || uri.hasPort ||
          uri.userInfo.isNotEmpty || uri.host.isEmpty) continue;
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host.endsWith('.local') ||
          host.endsWith('.localhost') || host.contains(':') ||
          RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(host) ||
          host.endsWith('a-ads.com')) continue;
      final path = uri.path.toLowerCase();
      if (path.endsWith('.svg') || path.endsWith('.gif') ||
          path.contains('placeholder') || path.contains('readerarea.svg')) continue;
      if (seen.add(uri.toString())) pages.add(PageRef(uri.toString()));
      if (pages.length == 300) break;
    }
    if (pages.isEmpty) {
      throw const FormatException('Aucune planche lisible dans le DOM rendu.');
    }
    return pages;
  }
}

/// Reads only the visible text of the rendered page (bounded) so the engine
/// can recognise a paywall, login wall, age gate or challenge BEFORE any
/// "page" is extracted. Clicks nothing, answers nothing, sends nothing.
const accessProbeScript = r'''
(() => {
  const text = ((document.body && document.body.innerText) || '').slice(0, 6000);
  const images = document.querySelectorAll('img').length;
  return JSON.stringify({url: location.href, title: document.title || '',
    text, images});
})()
''';
