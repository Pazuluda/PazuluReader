import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../engine/http/html_extract.dart';

/// One series of the official WEBTOON daily schedule (weekday, no hour).
class WebtoonDaily {
  const WebtoonDaily({required this.title, required this.url, required this.weekday,
      this.coverUrl});
  final String title;
  final String url;

  /// 1 = Monday … 7 = Sunday.
  final int weekday;
  final String? coverUrl;
}

/// Reads https://www.webtoons.com/{en,fr}/originals : series grouped by the
/// day they update. The page markup changes from time to time, so the
/// parser looks for any block labelled with a weekday that contains series
/// links (`…/list?title_no=…`), instead of one exact layout.
class WebtoonDailyParser {
  static const _days = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5,
    'saturday': 6, 'sunday': 7,
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  };

  static int? _weekdayOf(dom.Element e) {
    final label = [
      e.className, e.id, e.attributes['data-weekday'] ?? '', e.attributes['data-day'] ?? '',
    ].join(' ').toLowerCase();
    for (final m in RegExp(r'(?:_list_|list_|daily_|weekday[-_=]?|^|\s)([a-z]+)').allMatches(label)) {
      final d = _days[m.group(1)];
      if (d != null) return d;
    }
    return null;
  }

  static List<WebtoonDaily> parse(String body, Uri base) {
    final doc = html.parse(body);
    final out = <WebtoonDaily>[];
    final seen = <String>{};
    for (final block in doc.querySelectorAll('[class*="_list_"], [data-weekday], [class*="daily"], '
        'section[id], div[id]')) {
      final day = _weekdayOf(block);
      if (day == null) continue;
      for (final a in block.querySelectorAll('a[href*="title_no="]')) {
        final href = a.attributes['href'];
        if (href == null) continue;
        final url = base.resolve(href);
        if (!url.host.endsWith('webtoons.com')) continue;
        final titleNode = a.querySelector('.subj, .title, strong, .info_text .subj, p');
        final title = HtmlExtract.cleanText(titleNode?.text ?? a.attributes['title'] ?? a.text);
        if (title.length < 2 || title.length > 120) continue;
        final id = url.queryParameters['title_no'] ?? url.toString();
        if (!seen.add('$day|$id')) continue;
        out.add(WebtoonDaily(title: title, url: url.toString(), weekday: day,
            coverUrl: HtmlExtract.imageUrlOf(a.querySelector('img'), base)));
      }
    }
    return out;
  }
}
