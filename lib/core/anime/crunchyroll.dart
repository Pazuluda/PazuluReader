import 'dart:convert';

import 'anilist.dart';
import 'fr_planning.dart';

/// Crunchyroll, plateforme principale des animés dans Pazulu.
///
/// Pazulu sait quels animés sont sur Crunchyroll (liens officiels publiés
/// par AniList), date la sortie en France avec le planning français
/// hebdomadaire, puis ouvre l'épisode sur crunchyroll.com : dans le
/// navigateur intégré (site et lecteur officiels, compte de l'utilisateur)
/// ou dans Firefox pour « Roll With Your Friends ». Pazulu ne lit ni
/// n'extrait jamais la vidéo et ne voit jamais les identifiants.
class Crunchyroll {
  const Crunchyroll._();

  static bool isCrunchyrollUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'crunchyroll.com' || host.endsWith('.crunchyroll.com');
  }

  static bool _isCr(StreamingLink l) =>
      l.site.toLowerCase().contains('crunchyroll') || isCrunchyrollUrl(l.url);

  /// The series page on Crunchyroll, when AniList lists one.
  static StreamingLink? seriesLink(AnimeInfo info) {
    for (final l in info.streaming) {
      if (_isCr(l)) return l;
    }
    return null;
  }

  static bool isOn(AnimeInfo info) => seriesLink(info) != null;

  /// An episode page (« /watch/… »), not the series page.
  static bool isEpisodeUrl(String url) {
    final u = Uri.tryParse(url);
    return u != null && u.scheme == 'https' && isCrunchyrollUrl(url) && u.pathSegments.contains('watch');
  }

  /// Season number written in an AniList title: « Season 2 », « Saison 3 »,
  /// « 2nd Season », « Overlord III ». Null when there is none.
  static int? seasonNumber(String title) {
    final t = title.trim();
    final m = RegExp(r'(?:season|saison)\s*(\d{1,2})\b', caseSensitive: false).firstMatch(t) ??
        RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)\s+season\b', caseSensitive: false).firstMatch(t);
    if (m != null) return int.tryParse(m[1]!);
    final roman = RegExp(r'\s(II|III|IV|V|VI|VII|VIII)\s*$').firstMatch(t);
    if (roman != null) {
      return const {'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8}[roman[1]];
    }
    return null;
  }

  /// What helps to find the right Crunchyroll season for [info].
  static Map<String, Object?> seasonHints(AnimeInfo info) {
    int? season;
    for (final t in [info.title, ...info.altTitles]) {
      season ??= seasonNumber(t);
    }
    return {
      'season': season,
      'titles': [info.title, ...info.altTitles],
      'count': info.airedEpisodes ?? info.episodes,
      'sequel': info.relations.any((r) => r.relation == 'PREQUEL' && r.type == 'ANIME'),
    };
  }

  /// Script run in the Crunchyroll series page shown in Pazulu: finds
  /// episode [n] of the AniList season in Crunchyroll's own list, and puts
  /// the result in window.__pzFind ({state: running|done|fail, href}).
  ///
  /// Crunchyroll often keeps counting across seasons (Black Clover
  /// « Saison 2 » = E171…E176, « Saison 1 Partie 2 » = E52…E102). So:
  /// 1. the season is chosen in Crunchyroll's season menu (season number
  ///    of the AniList title, words of the title, number of episodes);
  /// 2. in that season, the n-th episode is taken (whatever its label:
  ///    E6 or E176), after « Voir plus » has loaded the whole list;
  /// 3. otherwise (one AniList entry over several Crunchyroll parts) the
  ///    label « E`n` » is looked for season after season.
  /// It only reads the page and uses the season menu; Pazulu opens the
  /// episode page itself.
  static String findEpisodeScript(int n, {Map<String, Object?> hints = const {}}) =>
      _finder.replaceAll('__N__', '$n').replaceAll('__HINTS__', jsonEncode(hints));

  /// Reads the search result (JSON or 'null').
  static const findEpisodeState = 'JSON.stringify(window.__pzFind || null)';

  static const _finder = r'''
(function (n, hints) {
  var key = location.pathname + '#' + n;
  if (window.__pzFind && window.__pzFind.key === key) return 'running';
  var st = window.__pzFind = { key: key, state: 'running', href: '', note: '' };
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  var norm = function (t) {
    return (t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, ' ').trim();
  };
  var EP = /^(?:E|É)(?:pisode\s*)?(\d+)\b/i;
  function cards() {
    var map = {}, nums = [];
    var links = document.querySelectorAll('a[href*="/watch/"]');
    for (var i = 0; i < links.length; i++) {
      var t = (links[i].textContent || '').trim();
      var m = t.match(EP);
      if (!m) continue;
      var k = parseInt(m[1], 10);
      if (!map[k]) { map[k] = links[i].href; nums.push(k); }
    }
    nums.sort(function (a, b) { return a - b; });
    return { map: map, nums: nums };
  }
  function current() {
    var t = document.querySelector('.erc-seasons-select .trigger-title');
    return t ? (t.textContent || '').trim() : '';
  }
  async function loadAll() {
    for (var i = 0; i < 12; i++) {
      var b = document.querySelector('[data-t="show-more-btn"]');
      if (!b) return;
      var before = cards().nums.length;
      b.click();
      for (var j = 0; j < 12 && cards().nums.length === before; j++) await sleep(250);
    }
  }
  async function settle(name) {
    for (var i = 0; i < 40; i++) {
      if ((!name || current() === name) && cards().nums.length) break;
      await sleep(250);
    }
    await sleep(400);
    await loadAll();
    return cards();
  }
  function inSeason(c) {
    if (!c.nums.length) return '';
    if (c.nums[0] === 1 && c.map[n]) return c.map[n];       // numbered from 1
    if (c.nums.length >= n) return c.map[c.nums[n - 1]];   // keeps counting: n-th
    return '';
  }
  function options() {
    var list = document.querySelectorAll('.erc-seasons-select [role="option"], [role="listbox"] [role="option"]');
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var o = list[i];
      var nameEl = o.querySelector('[class*="extended-option__text--"]') || o.querySelector('[class*="extended-option__text"]');
      var name = ((nameEl || o).textContent || '').trim();
      var desc = o.querySelector('[class*="extended-option__descripti"]');
      var cm = desc ? (desc.textContent || '').match(/(\d+)/) : null;
      out.push({ name: name, count: cm ? parseInt(cm[1], 10) : 0, index: i });
    }
    return out;
  }
  function score(o) {
    var s = 0, nn = norm(o.name);
    if (/\b(ova|oav|sp|special|speciaux|film|movie|recap|resume)\b/.test(nn)) s -= 6;
    if (/\b(doublage|dub|dubbed|vf|english|deutsch|espanol|italiano|portugues)\b/.test(nn)) s -= 3;
    if (hints.season) {
      var re = new RegExp('\\b(saison|season)\\s*' + hints.season + '\\b');
      if (re.test(nn)) s += 8;
      else if (/\b(saison|season)\s*\d+/.test(nn)) s -= 4;
    }
    var words = {};
    (hints.titles || []).forEach(function (t) {
      norm(t).split(' ').forEach(function (w) { if (w.length >= 4) words[w] = 1; });
    });
    var hit = 0;
    Object.keys(words).forEach(function (w) { if ((' ' + nn + ' ').indexOf(' ' + w + ' ') >= 0) hit++; });
    s += Math.min(hit, 3);
    if (hints.count && o.count === hints.count) s += 3;
    if (o.count && o.count < n) s -= 5;
    if (!hints.season && hints.sequel) s += o.index * 0.01;   // later seasons first
    if (!hints.season && !hints.sequel) s -= o.index * 0.01;  // first seasons first
    return s;
  }
  async function choose(o) {
    if (current() === o.name) return settle(o.name);
    var trigger = document.querySelector('.erc-seasons-select [role="button"]');
    if (!trigger) return cards();
    trigger.click();
    await sleep(500);
    var list = options(), el = null;
    var nodes = document.querySelectorAll('.erc-seasons-select [role="option"], [role="listbox"] [role="option"]');
    for (var i = 0; i < list.length; i++) if (list[i].name === o.name) { el = nodes[i]; break; }
    if (!el) { trigger.click(); return cards(); }
    el.click();
    return settle(o.name);
  }
  (async function () {
    try {
      for (var i = 0; i < 40 && !document.querySelector('.erc-seasons-select') && !cards().nums.length; i++) await sleep(250);
      var trigger = document.querySelector('.erc-seasons-select [role="button"]');
      if (!trigger) {                              // one season only
        var c0 = await settle('');
        st.href = inSeason(c0) || c0.map[n] || '';
        st.note = 'single';
      } else {
        trigger.click();
        await sleep(500);
        var opts = options();
        trigger.click();
        await sleep(300);
        var ranked = opts.slice().sort(function (a, b) { return score(b) - score(a); });
        var best = ranked[0];
        if (best && (!best.count || best.count >= n) && score(best) > -3) {
          var c = await choose(best);
          st.href = inSeason(c);
          st.note = 'season:' + best.name;
        }
        if (!st.href) {                            // label E<n> across seasons
          for (var k = 0; k < opts.length && !st.href; k++) {
            if (score(opts[k]) <= -6) continue;
            var c2 = await choose(opts[k]);
            if (c2.map[n]) { st.href = c2.map[n]; st.note = 'label:' + opts[k].name; }
          }
        }
      }
      if (st.href) {
        var c3 = cards();
        for (var key2 in c3.map) if (c3.map[key2] === st.href) st.label = parseInt(key2, 10);
      }
      st.state = st.href ? 'done' : 'fail';
    } catch (e) {
      st.state = 'fail';
      st.note = String(e);
    }
  })();
  return 'started';
})(__N__, __HINTS__)''';

  /// Direct link to episode [episode] when AniList has it, otherwise the
  /// series page (Crunchyroll lists the episodes there).
  static String? urlFor(AnimeInfo info, {int? episode}) {
    if (episode != null) {
      for (final e in info.episodeLinks) {
        if (e.number == episode && isCrunchyrollUrl(e.url)) return e.url;
      }
    }
    return seriesLink(info)?.url;
  }

  /// Minutes Crunchyroll is usually ahead of the French planning (the
  /// planning gives the time the episode is out in France on the sites
  /// it follows; Crunchyroll has it ~20 min before).
  static const defaultLeadMinutes = 20;

  /// When the episode that aired in Japan at [jpAiring] is out in France on
  /// Crunchyroll, from the French planning (null when it lacks it).
  static DateTime? frenchTime(FrPlanning? fr, AnimeInfo info, DateTime jpAiring,
      {int leadMinutes = defaultLeadMinutes}) {
    final at = fr?.releaseFor(info, jpAiring)?.at;
    return at?.subtract(Duration(minutes: leadMinutes));
  }

  /// Episodes out in the last [window], only series on Crunchyroll,
  /// newest first, one line per (series, episode). With the French
  /// planning, « out » means out in France (not just aired in Japan).
  static List<FreshEpisode> fresh(List<(AnimeAiring, AnimeInfo)> airings,
      {required DateTime now, Duration window = const Duration(days: 3),
      FrPlanning? fr, int leadMinutes = defaultLeadMinutes}) {
    final from = now.subtract(window);
    final seen = <String>{};
    final out = <FreshEpisode>[];
    for (final (a, info) in airings) {
      if (!isOn(info)) continue;
      final frAt = frenchTime(fr, info, a.airingAt, leadMinutes: leadMinutes);
      final at = frAt ?? a.airingAt;
      if (at.isAfter(now) || at.isBefore(from)) continue;
      if (!seen.add('${info.id}:${a.episode}')) continue;
      out.add(FreshEpisode(info: info, episode: a.episode, airedAt: at, jpAt: a.airingAt,
          french: frAt != null));
    }
    out.sort((x, y) => y.airedAt.compareTo(x.airedAt));
    return out;
  }
}

class FreshEpisode {
  const FreshEpisode({required this.info, required this.episode, required this.airedAt,
      DateTime? jpAt, this.french = false})
      : jpAt = jpAt ?? airedAt;
  final AnimeInfo info;
  final int episode;

  /// Out in France on Crunchyroll when [french], otherwise Japanese airing.
  final DateTime airedAt;
  final DateTime jpAt;
  final bool french;

  String? get url => Crunchyroll.urlFor(info, episode: episode);
}
