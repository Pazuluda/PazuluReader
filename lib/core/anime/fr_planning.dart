import 'dart:isolate';

import 'package:html/parser.dart' as html;

import '../../engine/http/engine_http.dart';
import 'anilist.dart';

/// One line of the French weekly planning (anime-sama.to/planning) : a
/// title, the French release time (VOSTFR / VF) and the season label.
///
/// Only the schedule is read (title + time). Pazulu opens no link of that
/// site: episodes are watched on Crunchyroll.
class FrRelease {
  const FrRelease({required this.title, required this.at, required this.lang,
      this.label = '', this.postponed = false});

  final String title;
  final DateTime? at;

  /// VOSTFR, VF or '' (unknown).
  final String lang;
  final String label;
  final bool postponed;

  String get key => FrPlanning.normalize(title);
}

class FrPlanning {
  FrPlanning(this.releases, {DateTime? fetchedAt}) : fetchedAt = fetchedAt ?? DateTime.now();

  final List<FrRelease> releases;
  final DateTime fetchedAt;

  static final Uri pageUri = Uri.parse('https://anime-sama.to/planning/');

  /// « Tensei Goblin Dakedo Shitsumon Aru? » → « tensei goblin dakedo shitsumon aru ».
  static String normalize(String s) {
    var t = s.toLowerCase();
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final b = StringBuffer();
    for (final ch in t.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    t = b.toString().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Reads the anime cards of the planning page (scans and webtoons are
  /// ignored). Pure function, runs in a background isolate.
  static List<FrRelease> parse(String page) {
    final doc = html.parse(page);
    final out = <FrRelease>[];
    for (final c in doc.querySelectorAll('.planning-card')) {
      final a = c.attributes;
      if ((a['data-card-type'] ?? '') != 'Anime') continue;
      final title = (a['data-nom'] ?? '').trim();
      if (title.isEmpty) continue;
      final ts = int.tryParse(a['data-release-ts'] ?? a['data-heure-ts'] ?? '');
      final label = c.querySelector('.as-carte-info span')?.text.trim() ?? '';
      out.add(FrRelease(
        title: title,
        at: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        lang: (a['data-carte-langue'] ?? '').trim().toUpperCase(),
        label: label,
        postponed: c.classes.contains('pl-reporte'),
      ));
    }
    return out;
  }

  static Future<FrPlanning> fetch(EngineHttpClient http) async {
    final r = await http.get(pageUri,
        allowedHosts: const ['anime-sama.to', 'anime-sama.tv', 'anime-sama.si', 'anime-sama.org'],
        timeout: const Duration(seconds: 20),
        headers: const {'Accept': 'text/html'});
    if (!r.ok) throw 'Planning FR indisponible (HTTP ${r.status})';
    final text = r.text;
    // ~600 Ko de HTML : analysé hors du fil de l'interface (pas de saccade).
    final list = await Isolate.run(() => parse(text));
    if (list.isEmpty) throw 'Planning FR illisible (aucun animé trouvé)';
    return FrPlanning(list);
  }

  /// Titles of [info] the planning may use (English, romaji, synonyms).
  static Set<String> keysOf(AnimeInfo info) => {
        for (final t in [info.title, ...info.altTitles])
          if (normalize(t).length >= 3) normalize(t),
      };

  static bool sameWork(String key, Set<String> keys) {
    if (keys.contains(key)) return true;
    // Un titre assez long qui commence l'autre (sous-titre ajouté).
    for (final k in keys) {
      final short = k.length < key.length ? k : key;
      final long = k.length < key.length ? key : k;
      if (short.length >= 12 && long.startsWith(short)) return true;
    }
    return false;
  }

  /// French release of the episode that aired in Japan at [jpAiring]:
  /// the planning line of this series between 3 h before and 48 h after
  /// (VOSTFR preferred). Null when the planning does not have it.
  FrRelease? releaseFor(AnimeInfo info, DateTime jpAiring) {
    final keys = keysOf(info);
    FrRelease? best;
    for (final r in releases) {
      final at = r.at;
      if (at == null || r.postponed) continue;
      if (at.isBefore(jpAiring.subtract(const Duration(hours: 3)))) continue;
      if (at.isAfter(jpAiring.add(const Duration(hours: 48)))) continue;
      if (!sameWork(r.key, keys)) continue;
      if (best == null || (best.lang != 'VOSTFR' && r.lang == 'VOSTFR') ||
          (best.lang == r.lang && at.isBefore(best.at!))) {
        best = r;
      }
    }
    return best;
  }

  /// The series is announced as postponed this week.
  bool postponed(AnimeInfo info) {
    final keys = keysOf(info);
    return releases.any((r) => r.postponed && sameWork(r.key, keys));
  }
}
