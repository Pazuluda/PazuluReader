import '../../core/models.dart';

/// Guards against attaching another work's chapters to a work.
///
/// Typical failure: a site no longer has the series, redirects the work URL
/// to its home page, and the home page lists the latest chapters of ALL its
/// series (3862, 877, 240…). Each guard alone is enough to reject that.
class ListingGuard {
  const ListingGuard._();

  static String _lastSegment(String path) =>
      path.split('/').where((s) => s.isNotEmpty).lastOrNull?.toLowerCase() ?? '';

  static String _normPath(String path) =>
      path.endsWith('/') ? path.toLowerCase() : '${path.toLowerCase()}/';

  /// Same page after redirects (host may change on a domain move, the path
  /// may not). A redirect to the home page or to another series is refused.
  static bool samePage(Uri requested, Uri received) {
    if (_normPath(requested.path) == _normPath(received.path)) return true;
    // Sites like AsuraScans move a series to a new address with a random
    // suffix (/series/solo-leveling-1f2e3d4c/ → /comics/solo-leveling-ab39de10):
    // same series slug once the suffix is removed. A home page has no slug.
    String core(Uri u) => _lastSegment(u.path).replaceFirst(RegExp(r'-[0-9a-f]{6,}$'), '');
    final a = core(requested);
    return a.length >= 4 && RegExp(r'[a-z]{3,}').hasMatch(a) && a == core(received);
  }

  /// Keeps only chapters whose URL belongs to the work page [workUrl]:
  /// under the work path (`/manga/solo-leveling/chapter-1/`) or carrying the
  /// work slug immediately followed by a chapter marker
  /// (`/solo-leveling-chapter-1/`). `/solo-leveling-ragnarok-chapter-5/` and
  /// `/martial-peak/chapter-3862/` are rejected.
  static List<SourceChapter> belongingTo(String workUrl, List<SourceChapter> chapters) {
    final work = Uri.tryParse(workUrl);
    if (work == null) return const [];
    final base = _normPath(work.path);
    final slug = _lastSegment(work.path);
    final hasWords = RegExp(r'[a-z]{3,}').hasMatch(slug);
    final slugPattern = hasWords
        ? RegExp('(?:^|[/_-])${RegExp.escape(slug)}'
            r'(?:$|/|[-_](?:chapter|chapitre|chap|ch|episode|ep|vol|volume|tome|'
            r'extra|bonus|special|side|prologue|epilogue|\d))')
        : null;
    return [
      for (final c in chapters)
        if (_belongs(c.isExternal ? c.externalUrl! : c.chapterId, base, slugPattern)) c,
    ];
  }

  static bool _belongs(String url, String base, RegExp? slugPattern) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    if (base.length > 1 && path.startsWith(base) && path.length > base.length) return true;
    return slugPattern != null && slugPattern.hasMatch(path);
  }

  static List<double> _numbers(Iterable<SourceChapter> chapters) {
    final out = <double>{
      for (final c in chapters)
        if (c.key.number case final double n) n,
    }.toList()
      ..sort();
    return out;
  }

  /// A listing whose numbers form distant islands (240, 877, 3862) is a
  /// mix of several works.
  static bool looksMixed(Iterable<SourceChapter> chapters) {
    // Chapter 0 / 0.5 (prologue) next to 179.5 … 200 (Solo Leveling on
    // SushiScan, after volumes 1–15) is one work, not two.
    final n = [for (final v in _numbers(chapters)) if (v >= 1) v];
    if (n.length < 2) return false;
    // Islands of numbers separated by big gaps. A real list has ONE main
    // island (maybe a few stray chapters: 1–3 kept as preview, then
    // 150–200). A home page of « latest updates » is made of many small
    // islands (240, 877, 3862…): no island holds most of the chapters.
    var biggest = 1;
    var current = 1;
    for (var i = 1; i < n.length; i++) {
      // Gap relative to where it starts: 240 → 877 is a jump, 1100 → 1180
      // is not.
      final limit = n[i - 1] * 0.35 < 80 ? 80 : n[i - 1] * 0.35;
      if (n[i] - n[i - 1] > limit) {
        current = 1;
      } else {
        current++;
      }
      if (current > biggest) biggest = current;
    }
    return biggest < n.length * 0.6;
  }

  /// Drops the chapters far ABOVE the main block of numbers (a « chapter
  /// 3862 » in a 200-chapter list is another series' link). Chapters below
  /// it (1–3 kept as preview) stay.
  static List<SourceChapter> withoutStrays(List<SourceChapter> chapters) {
    final n = [for (final v in _numbers(chapters)) if (v >= 1) v];
    if (n.length < 3) return chapters;
    var bestStart = 0, bestLen = 1, start = 0;
    for (var i = 1; i <= n.length; i++) {
      final cut = i == n.length ||
          n[i] - n[i - 1] > (n[i - 1] * 0.35 < 80 ? 80 : n[i - 1] * 0.35);
      if (cut) {
        if (i - start >= bestLen) {
          bestLen = i - start;
          bestStart = start;
        }
        start = i;
      }
    }
    final top = n[bestStart + bestLen - 1];
    return [
      for (final c in chapters)
        if (c.key.number == null || c.key.number! <= top) c,
    ];
  }

  /// The listing starts near chapter 1 and contains at least 85 % of the
  /// integer chapters up to its maximum (and at least 10 of them).
  static bool dense(Iterable<SourceChapter> chapters) {
    final ints = <int>{
      for (final n in _numbers(chapters)) if (n >= 1) n.floor(),
    }.toList()..sort();
    if (ints.length < 10 || ints.first > 3 || ints.last > 5000) return false;
    return ints.length >= (ints.last - ints.first + 1) * 0.85;
  }

  /// A list going far beyond EVERY other site of its language is another
  /// work with the same name, even when it is complete and gap-free: on one
  /// site « Solo Leveling: Ragnarok » was a fan series of 201 chapters while
  /// every other site stopped around 73. At least 2 other sites of that
  /// language (10 numbered chapters or more each) are needed to judge, and
  /// one single other site at the same level is enough to keep the list
  /// (no site is a reference, the most advanced one is the measure).
  static String? farBeyondAllPeers(List<SourceChapter> candidate, Iterable<List<SourceChapter>> others) {
    final byLang = <String, List<double>>{};
    for (final c in candidate) {
      final n = c.key.number;
      if (!c.isExternal && n != null && n >= 1) byLang.putIfAbsent(c.lang, () => []).add(n);
    }
    for (final e in byLang.entries) {
      final lang = e.key;
      final mine = e.value..sort();
      final peerMax = <double>[];
      for (final list in others) {
        final nums = <double>{
          for (final c in list)
            if (c.lang == lang && !c.isExternal && c.key.number != null && c.key.number! >= 1) c.key.number!,
        };
        if (nums.length >= 10) peerMax.add(nums.reduce((a, b) => a > b ? a : b));
      }
      if (peerMax.length < 2) continue;
      final best = peerMax.reduce((a, b) => a > b ? a : b);
      final limit = best * 1.3 + 15;
      final beyond = mine.where((n) => n > limit).length;
      if (mine.last > limit && beyond >= 10) {
        return 'chapitre ${_fmt(mine.last)} ($lang) alors que les ${peerMax.length} autres sites '
            's\'arrêtent au plus au ${_fmt(best)} : autre œuvre du même nom';
      }
    }
    return null;
  }

  /// Vote between the sites of each language when they disagree on how
  /// far the series goes. [lists]: one entry per source, [siteOf] the site
  /// a source belongs to (the same site attached twice votes once).
  ///
  /// The sites are grouped by level (same last chapter, within 15 %). A
  /// group far above the level of the largest group (more than 1.3 × + 15)
  /// is another work of the same name (the NOVEL « Solo Leveling:
  /// Ragnarok », ~200 chapters, on 2 sites, while 4 sites have the 72–75
  /// chapters of the webtoon), when the largest group is current (a chapter
  /// dated in the last 30 days) or, without dates, at least twice as big.
  /// Returns the rejected source → reason. [protect]ed sources (opened by
  /// the user, connectors reading one series by id) vote but are never
  /// rejected.
  static Map<String, String> minorityLevels(Map<String, List<SourceChapter>> lists,
      {required String Function(String sourceId) siteOf, Set<String> protect = const {},
      DateTime? now}) {
    final at = now ?? DateTime.now();
    final out = <String, String>{};
    final langs = <String>{for (final l in lists.values) for (final c in l) c.lang};
    for (final lang in langs) {
      // site → (max, newest date, sources)
      final bySite = <String, (double, DateTime?, Set<String>)>{};
      for (final e in lists.entries) {
        final nums = <double>{};
        DateTime? newest;
        for (final c in e.value) {
          final n = c.key.number;
          if (c.lang != lang || c.isExternal || n == null || n < 1) continue;
          nums.add(n);
          final d = c.publishedAt;
          if (d != null && (newest == null || d.isAfter(newest))) newest = d;
        }
        if (nums.length < 10) continue;
        final max = nums.reduce((a, b) => a > b ? a : b);
        final site = siteOf(e.key);
        final old = bySite[site];
        if (old == null) {
          bySite[site] = (max, newest, {e.key});
        } else {
          final oldDate = old.$2;
          bySite[site] = (
            max > old.$1 ? max : old.$1,
            oldDate == null || (newest != null && newest.isAfter(oldDate)) ? newest : oldDate,
            {...old.$3, e.key},
          );
        }
      }
      if (bySite.length < 4) continue;
      bool sameLevel(double a, double b) => (a - b).abs() <= (a > b ? a : b) * 0.15 + 5;
      final sites = bySite.entries.toList();
      int support(double m) => sites.where((s) => sameLevel(s.value.$1, m)).length;
      // Largest group; on a tie, the lower level (fewer false chapters).
      var ref = sites.first;
      for (final s in sites) {
        final a = support(s.value.$1), b = support(ref.value.$1);
        if (a > b || (a == b && s.value.$1 < ref.value.$1)) ref = s;
      }
      final refMax = ref.value.$1;
      final refSupport = support(refMax);
      final refCurrent = sites.any((s) =>
          sameLevel(s.value.$1, refMax) && s.value.$2 != null &&
          at.difference(s.value.$2!) <= const Duration(days: 30));
      for (final s in sites) {
        final m = s.value.$1;
        if (m <= refMax * 1.3 + 15) continue;
        final mine = support(m);
        if (mine >= refSupport) continue;
        if (!refCurrent && refSupport < mine * 2) continue;
        for (final id in s.value.$3) {
          if (protect.contains(id)) continue;
          out[id] = 'chapitre ${_fmt(m)} ($lang) alors que $refSupport sites '
              '${refCurrent ? 'à jour ' : ''}s\'arrêtent vers le ${_fmt(refMax)} '
              '(seulement $mine site(s) à ce niveau) : autre œuvre du même nom';
        }
      }
    }
    return out;
  }

  /// Why [candidate] (a web site's chapters) cannot be the same work as the
  /// trusted [reference] chapters (API connectors, local copies), or null.
  static String? rejectReason(List<SourceChapter> candidate, List<SourceChapter> reference,
      {bool checkMixed = true}) {
    if (checkMixed && looksMixed(candidate)) {
      return 'numéros de chapitres dispersés (plusieurs œuvres mélangées)';
    }
    // A complete, gap-free series list (1, 2, 3 … 330) is a real chapter
    // list, even when the API connectors only know the first 50 chapters
    // (licensed series are often truncated there). Home pages of « latest
    // updates » are never dense.
    if (dense(candidate)) return null;
    final ref = _numbers(reference);
    final cand = _numbers(candidate);
    if (ref.length < 5 || cand.isEmpty) return null;
    final refMax = ref.last;
    if (cand.last > refMax * 3 + 50) {
      return 'chapitre ${_fmt(cand.last)} pour une œuvre connue jusqu\'au ${_fmt(refMax)}';
    }
    final limit = refMax * 1.3 + 15;
    final outside = cand.where((n) => n > limit).length;
    if (outside > cand.length * 0.2) {
      return '$outside chapitre(s) au-delà du dernier chapitre connu (${_fmt(refMax)})';
    }
    return null;
  }

  static String _fmt(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  /// The result link of a search card must agree with the card title: a
  /// slug made of words shares at least one significant word with it.
  /// Numeric slugs (`/series/12345`) and non-latin titles are not judged.
  static bool slugAgreesWithTitle(String url, String title) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final slugWords = _lastSegment(uri.path)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3 && RegExp(r'[a-z]').hasMatch(w))
        .toSet();
    if (slugWords.isEmpty) return true;
    final titleWords = _fold(title)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3)
        .toSet();
    if (titleWords.isEmpty) return true;
    return slugWords.any(titleWords.contains);
  }

  static String _fold(String s) {
    const map = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e',
      'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o',
      'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ñ': 'n', 'œ': 'oe',
    };
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }
}
