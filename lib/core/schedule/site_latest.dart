import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../engine/http/html_extract.dart';
import '../chapter_key.dart';

/// One chapter shown in a site's « latest updates » block.
class SiteRelease {
  const SiteRelease({
    required this.seriesTitle,
    required this.seriesUrl,
    required this.chapter,
    required this.at,
    required this.precise,
    this.coverUrl,
  });

  final String seriesTitle;
  final String seriesUrl;
  final ChapterKey chapter;
  final DateTime at;

  /// The site gave minutes/hours (« 2 hours ago »), not only a day.
  final bool precise;
  final String? coverUrl;
}

/// Release times written by sites: « 2 hours ago », « il y a 3 heures »,
/// « 1 day ago », « November 6, 2026 », « 06/11/2026 », « 6 novembre 2026 ».
class ReleaseTimeParser {
  static const _months = {
    'jan': 1, 'janv': 1, 'janvier': 1, 'january': 1,
    'feb': 2, 'fev': 2, 'fevr': 2, 'février': 2, 'fevrier': 2, 'févr': 2, 'february': 2,
    'mar': 3, 'mars': 3, 'march': 3,
    'apr': 4, 'avr': 4, 'avril': 4, 'april': 4,
    'may': 5, 'mai': 5,
    'jun': 6, 'juin': 6, 'june': 6,
    'jul': 7, 'juil': 7, 'juillet': 7, 'july': 7,
    'aug': 8, 'aout': 8, 'août': 8, 'august': 8,
    'sep': 9, 'sept': 9, 'septembre': 9, 'september': 9,
    'oct': 10, 'octobre': 10, 'october': 10,
    'nov': 11, 'novembre': 11, 'november': 11,
    'dec': 12, 'déc': 12, 'decembre': 12, 'décembre': 12, 'december': 12,
  };

  /// (date, precise) or null when the text holds no recognisable time.
  static (DateTime, bool)? parse(String raw, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final t = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    if (RegExp(r'\b(just now|now|à l.instant|maintenant|new)\b').hasMatch(t)) return (at, true);
    if (RegExp(r"\b(today|aujourd.hui)\b").hasMatch(t)) return (at, false);
    if (RegExp(r'\b(yesterday|hier)\b').hasMatch(t)) {
      return (at.subtract(const Duration(days: 1)), false);
    }
    final rel = RegExp(
            r'(\d+|an|a|une?|one)\s*(sec|second|seconde|min|minute|mins|h|hr|hrs|hour|heure|d|day|jour|j|w|week|semaine|month|mois|year|an|ans|année)s?\b')
        .firstMatch(t);
    final looksRelative = t.contains('ago') || t.contains('il y a') ||
        RegExp(r'^\d+\s*(min|h|d|j|w)s?$').hasMatch(t);
    if (rel != null && looksRelative) {
      final nText = rel.group(1)!;
      final n = int.tryParse(nText) ?? 1;
      final unit = rel.group(2)!;
      Duration d;
      var precise = true;
      if (unit.startsWith('sec')) {
        d = Duration(seconds: n);
      } else if (unit.startsWith('min')) {
        d = Duration(minutes: n);
      } else if (unit == 'h' || unit.startsWith('hr') || unit.startsWith('hour') ||
          unit.startsWith('heure')) {
        d = Duration(hours: n);
      } else if (unit == 'd' || unit.startsWith('day') || unit == 'j' || unit.startsWith('jour')) {
        d = Duration(days: n);
        precise = false;
      } else if (unit == 'w' || unit.startsWith('week') || unit.startsWith('semaine')) {
        d = Duration(days: 7 * n);
        precise = false;
      } else if (unit.startsWith('month') || unit == 'mois') {
        d = Duration(days: 30 * n);
        precise = false;
      } else {
        d = Duration(days: 365 * n);
        precise = false;
      }
      return (at.subtract(d), precise);
    }
    // 2026-11-06
    final iso = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) {
      return _date(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
    // 06/11/2026 (sites FR) — day first.
    final dmy = RegExp(r'(\d{1,2})[/.](\d{1,2})[/.](\d{4})').firstMatch(t);
    if (dmy != null) {
      return _date(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
    }
    // November 6, 2026
    final mdy = RegExp(r'([a-zéû]+)\.? (\d{1,2}),? (\d{4})').firstMatch(t);
    if (mdy != null && _months[mdy.group(1)] != null) {
      return _date(int.parse(mdy.group(3)!), _months[mdy.group(1)]!, int.parse(mdy.group(2)!));
    }
    // 6 novembre 2026
    final dMy = RegExp(r'(\d{1,2}) ([a-zéû]+)\.? (\d{4})').firstMatch(t);
    if (dMy != null && _months[dMy.group(2)] != null) {
      return _date(int.parse(dMy.group(3)!), _months[dMy.group(2)]!, int.parse(dMy.group(1)!));
    }
    return null;
  }

  static (DateTime, bool)? _date(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000) return null;
    return (DateTime(y, m, d), false);
  }
}

/// Reads the « latest updates » block of Madara and MangaThemesia home
/// pages (the two families of most directory sites). Metadata only.
class SiteLatestParser {
  static List<SiteRelease> parse(String body, Uri base, {DateTime? now, int limit = 60}) {
    final doc = html.parse(body);
    final out = <SiteRelease>[];
    final seen = <String>{};

    void add(String? title, String? seriesHref, String? chapterText, String? timeText,
        dom.Element? card) {
      if (title == null || seriesHref == null || chapterText == null || timeText == null) return;
      final cleanTitle = HtmlExtract.cleanText(title);
      if (cleanTitle.length < 2) return;
      final key = ChapterKey.parse(chapterText);
      if (key.number == null) return;
      final time = ReleaseTimeParser.parse(timeText, now: now);
      if (time == null) return;
      final url = base.resolve(seriesHref.trim());
      if (url.host != base.host && !url.host.endsWith('.${base.host}')) return;
      final id = '$url|${key.id}';
      if (!seen.add(id)) return;
      out.add(SiteRelease(
        seriesTitle: cleanTitle,
        seriesUrl: url.toString(),
        chapter: key,
        at: time.$1,
        precise: time.$2,
        coverUrl: card == null ? null : HtmlExtract.imageUrlOf(card.querySelector('img'), base),
      ));
    }

    // Madara: .page-item-detail > .post-title a, .chapter-item (.chapter a + .post-on)
    for (final card in doc.querySelectorAll('.page-item-detail, .c-tabs-item__content')) {
      final series = card.querySelector('.post-title a, h3 a, .h5 a');
      for (final item in card.querySelectorAll('.chapter-item, .list-chapter .chapter-item')) {
        final ch = item.querySelector('.chapter a, a');
        // « 2 hours ago » is often in the title of a link inside .post-on.
        final titled = item.querySelector('.post-on a[title]');
        final timeNode = titled ?? item.querySelector('.post-on, .chapter-release-date');
        final time = titled?.attributes['title'] ?? timeNode?.text;
        add(series?.text, series?.attributes['href'], ch?.text, time, card);
      }
    }
    // MangaThemesia: .utao .uta (.luf h4/h3 a + ul li (a, span))
    for (final card in doc.querySelectorAll('.utao .uta, .uta')) {
      final series = card.querySelector('.luf a.series, .luf h4 a, .luf h3 a, .luf a');
      final title = card.querySelector('.luf h4, .luf h3')?.text ?? series?.attributes['title'] ??
          series?.text;
      for (final li in card.querySelectorAll('.luf ul li, ul li')) {
        final ch = li.querySelector('a');
        final time = li.querySelector('span, i')?.text;
        add(title, series?.attributes['href'], ch?.text, time, card);
      }
    }
    // MangaThemesia (bixbox listupd variant): .bs .bsx with .epxs and .epxdate
    for (final card in doc.querySelectorAll('.listupd .bs .bsx')) {
      final a = card.querySelector('a');
      add(a?.attributes['title'] ?? card.querySelector('.tt')?.text, a?.attributes['href'],
          card.querySelector('.epxs, .adds .epxs')?.text,
          card.querySelector('.epxdate')?.text, card);
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out.length > limit ? out.sublist(0, limit) : out;
  }
}
