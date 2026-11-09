import 'dart:convert';

import 'package:html/dom.dart' as dom;

/// Shared HTML helpers for the HTTP/HTML connectors. They read ordinary
/// public markup and inline JSON reader configurations only. Encrypted or
/// obfuscated readers ("chapter protector", canvas scramblers, DRM) are
/// reported as unsupported, never decoded.
class HtmlExtract {
  const HtmlExtract._();

  static const imageAttributes = <String>[
    'data-src', 'data-lazy-src', 'data-original', 'data-cfsrc', 'data-url',
    'data-image', 'data-srcset', 'data-lazy-srcset', 'srcset', 'src',
  ];

  static final RegExp _badPath = RegExp(
      r'\.svg$|\.ico$|placeholder|readerarea\.svg|loading\.|lazy\.(?:gif|png)|'
      r'blank\.(?:gif|png)|spacer\.gif',
      caseSensitive: false);

  /// Best real image URL of an `<img>`, `<source>` or `<picture>`, resolving lazy
  /// attributes (`data-src`, `srcset`…) against [base].
  static String? imageUrlOf(dom.Element? node, Uri base) {
    if (node == null) return null;
    if (node.localName == 'picture') {
      for (final child in node.querySelectorAll('source, img')) {
        final found = imageUrlOf(child, base);
        if (found != null) return found;
      }
      return null;
    }
    for (final name in imageAttributes) {
      final value = node.attributes[name]?.trim();
      if (value == null || value.isEmpty) continue;
      final candidates = name.endsWith('srcset') ? _srcsetCandidates(value) : [value];
      for (final candidate in candidates) {
        final resolved = resolveImage(candidate, base);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  /// Largest candidate first: `a.jpg 800w, b.jpg 1600w` -> b.jpg, a.jpg.
  static List<String> _srcsetCandidates(String value) {
    final parts = <(String, double)>[];
    for (final raw in value.split(RegExp(r',\s+(?=\S)'))) {
      final bits = raw.trim().split(RegExp(r'\s+'));
      if (bits.isEmpty || bits.first.isEmpty) continue;
      var weight = 0.0;
      if (bits.length > 1) {
        final d = RegExp(r'^(\d+(?:\.\d+)?)[wx]$').firstMatch(bits[1]);
        weight = d == null ? 0 : double.parse(d.group(1)!);
      }
      parts.add((bits.first, weight));
    }
    parts.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final p in parts) p.$1];
  }

  static String? resolveImage(String candidate, Uri base) {
    final c = candidate.trim();
    if (c.isEmpty || c == '#' || c.startsWith('data:') || c.startsWith('blob:') ||
        c.startsWith('javascript:')) {
      return null;
    }
    Uri uri;
    try {
      uri = base.resolve(c);
    } catch (_) {
      return null;
    }
    if (uri.scheme == 'http' && uri.host.isNotEmpty) {
      // Many sites still write http:// in markup for https-capable CDNs.
      uri = uri.replace(scheme: 'https');
    }
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    if (_badPath.hasMatch(uri.path) || uri.host.endsWith('a-ads.com')) return null;
    return uri.toString();
  }

  /// Ordered, de-duplicated page images inside the reader containers.
  static List<String> readerImages(dom.Document doc, List<String> selectors, Uri base,
      {int max = 400}) {
    final out = <String>[];
    final seen = <String>{};
    final nodes = <dom.Element>[];
    final visited = <dom.Element>{};
    for (final selector in selectors) {
      List<dom.Element> found;
      try {
        found = doc.querySelectorAll(selector);
      } catch (_) {
        continue; // unsupported selector syntax in package:html
      }
      for (final node in found) {
        if (visited.add(node)) nodes.add(node);
      }
    }
    // Keep document order even when several selectors matched.
    final order = <dom.Element, int>{};
    var i = 0;
    for (final el in doc.querySelectorAll('img, source, picture')) {
      order[el] = i++;
    }
    nodes.sort((a, b) => (order[a] ?? 1 << 30).compareTo(order[b] ?? 1 << 30));
    final handled = <dom.Element>{};
    for (final node in nodes) {
      // <picture><source/><img/></picture> is ONE page: resolve it once,
      // otherwise the webp source and jpeg fallback would become two pages.
      final parent = node.parent;
      final target = (node.localName == 'source' || node.localName == 'img') &&
              parent != null && parent.localName == 'picture'
          ? parent
          : node;
      if (!handled.add(target)) continue;
      final url = imageUrlOf(target, base);
      if (url != null && seen.add(url)) out.add(url);
      if (out.length >= max) break;
    }
    // <noscript> fallbacks are sometimes kept as raw text by the parser.
    if (out.isEmpty) {
      for (final ns in doc.querySelectorAll('noscript')) {
        for (final m in RegExp(r'''<img[^>]+(?:data-src|src)=["']([^"']+)["']''',
            caseSensitive: false).allMatches(ns.innerHtml)) {
          final url = resolveImage(m.group(1)!, base);
          if (url != null && seen.add(url)) out.add(url);
        }
      }
    }
    return out;
  }

  /// MangaThemesia readers (`ts_reader.run({...})`) put every page URL in an
  /// inline JSON object while `#readerarea` stays empty until JavaScript runs.
  /// Returns null when absent.
  static TsReaderConfig? tsReader(String html) {
    final start = html.indexOf('ts_reader.run(');
    if (start < 0) return null;
    final open = html.indexOf('{', start);
    if (open < 0) return null;
    final json = _balancedObject(html, open);
    if (json == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final sources = decoded['sources'];
    final servers = <List<String>>[];
    if (sources is List) {
      for (final s in sources) {
        if (s is! Map || s['images'] is! List) continue;
        servers.add([
          for (final img in s['images'] as List)
            if (img is String && img.trim().isNotEmpty) img.trim(),
        ]);
      }
    }
    return TsReaderConfig(
      servers: servers,
      prevUrl: decoded['prevUrl'] is String ? decoded['prevUrl'] as String : null,
      nextUrl: decoded['nextUrl'] is String ? decoded['nextUrl'] as String : null,
      protected: decoded['protected'] == true || decoded['noimagehtml'] is String &&
          servers.every((s) => s.isEmpty),
    );
  }

  /// Madara "preloaded images" variable, when present in clear text.
  /// Chapter images written inside the page's scripts / JSON (Next.js
  /// « __NEXT_DATA__ », Nuxt, Astro, inline arrays…), for sites whose
  /// reader draws the pages with JavaScript. The images of one chapter
  /// share a folder: the biggest group of image addresses in the same
  /// folder is kept, in page order. Logos, avatars and covers are ignored.
  static List<String> embeddedImages(String raw, Uri base) {
    final text = raw
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u002f', '/')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
    final found = <String>[];
    final seen = <String>{};
    final pattern = RegExp(
        r'''(https?://[^\s"'<>()\\]+?|/[^\s"'<>()\\:]+?)\.(?:jpe?g|png|webp|avif|gif)(?:\?[^\s"'<>\\]*)?(?=["'\s,\])}])''',
        caseSensitive: false);
    for (final m in pattern.allMatches(text)) {
      final value = m.group(0)!;
      final lower = value.toLowerCase();
      if (RegExp(r'logo|icon|avatar|favicon|banner|thumb|cover|gravatar|emoji|sprite|/ads?/|badge|flag')
          .hasMatch(lower)) {
        continue;
      }
      Uri? uri;
      try {
        uri = base.resolve(value);
      } catch (_) {
        continue;
      }
      if (uri.scheme != 'https' && uri.scheme != 'http') continue;
      final url = uri.replace(scheme: 'https').toString();
      if (seen.add(url)) found.add(url);
    }
    final groups = <String, List<String>>{};
    for (final u in found) {
      final path = Uri.parse(u).path;
      final folder = '${Uri.parse(u).host}${path.substring(0, path.lastIndexOf('/') + 1)}';
      groups.putIfAbsent(folder, () => []).add(u);
    }
    List<String> best = const [];
    for (final g in groups.values) {
      if (g.length > best.length) best = g;
    }
    return best.length >= 3 ? best : const [];
  }

  static List<String>? madaraPreloaded(String html) {
    final m = RegExp(r'chapter_preloaded_images\s*=\s*(\[[\s\S]*?\])\s*[,;]').firstMatch(html);
    if (m == null) return null;
    try {
      final list = jsonDecode(m.group(1)!);
      if (list is! List) return null;
      return [for (final e in list) if (e is String && e.isNotEmpty) e];
    } catch (_) {
      return null;
    }
  }

  /// Signals of an encrypted/obfuscated reader we must not attempt to decode.
  static bool looksProtected(String html) {
    final lower = html.toLowerCase();
    return lower.contains('chapter-protector') || lower.contains('chapter_protector') ||
        lower.contains('wpmangaprotector') || lower.contains('drm-viewer');
  }

  static String? _balancedObject(String text, int open) {
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = open; i < text.length && i < open + 2000000; i++) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == 0x5C) {
          escape = true;
        } else if (c == 0x22) {
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return text.substring(open, i + 1);
      }
    }
    return null;
  }

  /// Text of an element with a space between its pieces: « Chapter 272 »
  /// + « 28 Oct » must not become « Chapter 27228 Oct ».
  static String spacedText(dom.Element e) {
    final b = StringBuffer();
    void walk(dom.Node n) {
      if (n is dom.Text) {
        b
          ..write(n.text)
          ..write(' ');
      } else {
        for (final c in n.nodes) {
          walk(c);
        }
      }
    }
    walk(e);
    return cleanText(b.toString());
  }

  static String cleanText(String? text) =>
      (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class TsReaderConfig {
  const TsReaderConfig({required this.servers, this.prevUrl, this.nextUrl,
    this.protected = false});

  /// One list of page URLs per mirror server, in reading order.
  final List<List<String>> servers;
  final String? prevUrl;
  final String? nextUrl;
  final bool protected;

  List<String> get primary => servers.isEmpty ? const [] : servers.first;
}
