import 'package:html/parser.dart' as html_parser;

import 'site_index.dart';

/// One link of a browser bookmarks export (Chrome, Edge, Firefox, Opera:
/// « Exporter les favoris / marque-pages au format HTML »).
class Bookmark {
  const Bookmark(this.title, this.url);

  final String title;
  final String url;
}

/// A reading found in the bookmarks: the series (site + page when known)
/// and the chapter the bookmark points to, if it says so.
class BookmarkReading {
  BookmarkReading({
    required this.title,
    required this.bookmarkUrl,
    this.sourceId,
    this.seriesUrl,
    this.chapter,
  });

  final String title;
  final String bookmarkUrl;
  final String? sourceId;
  final String? seriesUrl;
  final double? chapter;

  String get key => SiteTitleIndex.norm(title);
}

/// Reads the links of an exported bookmarks file. Only the file chosen by
/// the user is read (never the browser's own profile folder).
List<Bookmark> parseBookmarksHtml(String text) {
  final doc = html_parser.parse(text);
  final out = <Bookmark>[];
  for (final a in doc.querySelectorAll('a')) {
    final href = a.attributes['href'] ?? a.attributes['HREF'];
    if (href == null || !(href.startsWith('http://') || href.startsWith('https://'))) continue;
    out.add(Bookmark(a.text.trim(), href.trim()));
  }
  return out;
}

final RegExp _chapterInUrl = RegExp(
    r'(?:chap(?:ter|itre)?|ch|episode|ep|scan)[-_/ .]*(\d+(?:[.-]\d+)?)(?:[^\d]|$)',
    caseSensitive: false);
final RegExp _chapterInTitle = RegExp(
    r'(?:chap(?:ter|itre)?\.?|ch\.|ch |ép(?:isode)?\.?|episode|scan)\s*#?(\d+(?:[.,]\d+)?)',
    caseSensitive: false);
final RegExp _titleCut = RegExp(
    r'\s*(?:[-–—|:•]\s*)?(?:chap(?:ter|itre)?\.?|ch\.|ép(?:isode)?|episode|scan|vol(?:ume)?\.?)\s*#?\d.*$',
    caseSensitive: false);
final RegExp _siteSuffix = RegExp(r'\s+[-–—|]\s+[^-–—|]{2,40}$');

/// « https://www.Site.com/manga/x/ » → « site.com/manga/x ».
String normalizeBookmarkUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url.trim().toLowerCase();
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$host$path';
}

String hostOf(String url) {
  final h = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  return h.startsWith('www.') ? h.substring(4) : h;
}

double? chapterFromBookmark(Bookmark b, {String rest = ''}) {
  final inUrl = _chapterInUrl.firstMatch(rest.isEmpty ? b.url : rest);
  if (inUrl != null) {
    return double.tryParse(inUrl.group(1)!.replaceAll('-', '.'));
  }
  if (rest.isNotEmpty) {
    // « /manga/solo-leveling/120/ »: a bare number right after the series.
    final seg = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.length == 1 && RegExp(r'^\d+(?:[.-]\d+)?$').hasMatch(seg.first)) {
      return double.tryParse(seg.first.replaceAll('-', '.'));
    }
  }
  final inTitle = _chapterInTitle.firstMatch(b.title);
  return inTitle == null ? null : double.tryParse(inTitle.group(1)!.replaceAll(',', '.'));
}

/// Title of an imported work without the marks some browsers / sites add
/// (« Reincarnator's Stream » », « … », « | »).
String cleanImportedTitle(String raw) => raw
    .replaceAll(RegExp(r'[\s»«›‹|•·…>-]+$'), '')
    .replaceAll(RegExp(r'^[\s»«›‹|•·…<-]+'), '')
    .trim();

/// « Solo Leveling - Chapitre 120 - MangaSite » → « Solo Leveling ».
String titleFromBookmark(String raw) {
  var t = raw.trim();
  final cut = t.replaceFirst(_titleCut, '').trim();
  if (cut.isNotEmpty && cut != t) {
    t = cut;
  } else {
    t = t.replaceFirst(_siteSuffix, '').trim();
  }
  for (final w in const ['Lire ', 'Read ', 'Scan ']) {
    if (t.startsWith(w)) t = t.substring(w.length);
  }
  return cleanImportedTitle(
      t.replaceAll(RegExp(r'\s+(VF|FR|Raw|Manga|Manhwa|Scan)$', caseSensitive: false), ''));
}

/// Finds the readings in [marks]:
/// - on a known site, the series is the catalogue entry whose address
///   starts the bookmark's address (exact, no guess);
/// - otherwise the bookmark's title is looked up in every site's catalogue
///   ([titleKnown]), and only kept when it points to a chapter, so that
///   ordinary bookmarks (videos, shops…) are never imported.
/// One reading per series: the highest chapter wins.
List<BookmarkReading> findReadings(
  List<Bookmark> marks, {
  required String? Function(String host) sourceForHost,
  required List<IndexedTitle> Function(String sourceId) titlesOf,
  required bool Function(String title) titleKnown,
}) {
  final bySourceUrl = <String, Map<String, IndexedTitle>>{};
  Map<String, IndexedTitle> urlsOf(String sourceId) => bySourceUrl[sourceId] ??= {
        for (final t in titlesOf(sourceId)) normalizeBookmarkUrl(t.url): t,
      };

  final best = <String, BookmarkReading>{};
  void keep(BookmarkReading r) {
    final k = r.key;
    if (k.length < 2) return;
    final old = best[k];
    if (old == null ||
        (r.chapter ?? -1) > (old.chapter ?? -1) ||
        (old.seriesUrl == null && r.seriesUrl != null && (r.chapter ?? -1) >= (old.chapter ?? -1))) {
      best[k] = r;
    }
  }

  for (final b in marks) {
    final host = hostOf(b.url);
    if (host.isEmpty) continue;
    final sourceId = sourceForHost(host);
    if (sourceId != null) {
      final urls = urlsOf(sourceId);
      final norm = normalizeBookmarkUrl(b.url);
      // Longest catalogue address that starts the bookmark's address.
      var probe = norm;
      IndexedTitle? series;
      while (probe.contains('/')) {
        series = urls[probe];
        if (series != null) break;
        probe = probe.substring(0, probe.lastIndexOf('/'));
      }
      if (series != null) {
        keep(BookmarkReading(
          title: series.title,
          bookmarkUrl: b.url,
          sourceId: sourceId,
          seriesUrl: series.url,
          chapter: chapterFromBookmark(b, rest: norm.substring(probe.length)),
        ));
        continue;
      }
    }
    final chapter = chapterFromBookmark(b);
    final title = titleFromBookmark(b.title);
    if (title.length < 2) continue;
    // A known reading site with an unknown page, or any site when the
    // bookmark clearly points to a chapter of a title the catalogues know.
    if ((sourceId != null || chapter != null) && titleKnown(title)) {
      keep(BookmarkReading(title: title, bookmarkUrl: b.url, sourceId: sourceId, chapter: chapter));
    }
  }
  return best.values.toList()..sort((a, b) => a.key.compareTo(b.key));
}
