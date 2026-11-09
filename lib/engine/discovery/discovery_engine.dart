import '../../core/models.dart';
import '../../core/source.dart';
import '../diagnostics/engine_log.dart';

/// Title normalisation shared by search grouping and source matching.
class TitleNormalizer {
  const TitleNormalizer._();

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y',
    'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
  };

  /// "Moi, quand je me réincarne en Slime" -> "moi quand je me reincarne en slime"
  static String normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_accents[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r"[’'`´]"), '')
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9぀-ヿ一-鿿가-힯]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Distinctive aliases only (≥ 4 characters after normalisation).
  static Set<String> aliases(WorkInfo w) => {
        for (final t in [w.title, ...w.altTitles])
          if (normalize(t).length >= 4) normalize(t),
      };
}

enum MatchReason { stableId, exactAlias, none }

/// One work grouped across sources (editions kept apart).
class WorkCluster {
  WorkCluster(this.primary) : members = [primary];

  WorkInfo primary;
  final List<WorkInfo> members;
  MatchReason reason = MatchReason.none;

  Set<String> get sourceIds => {for (final w in members) for (final l in w.links) l.sourceId};
  Set<String> get languages => {for (final w in members) ...w.languages};

  /// Merged fiche: links and languages of every member, metadata of primary.
  WorkInfo get merged {
    final links = <String, SourceLink>{};
    for (final w in members) {
      for (final l in w.links) {
        links['${l.sourceId}:${l.workId}'] = l;
      }
    }
    String pick(String Function(WorkInfo w) f) =>
        members.map(f).firstWhere((v) => v.isNotEmpty, orElse: () => '');
    return WorkInfo(
      id: primary.id,
      title: primary.title,
      altTitles: {for (final w in members) ...[w.title, ...w.altTitles]}
          .where((t) => t != primary.title).take(24).toList(),
      description: pick((w) => w.description),
      coverUrl: members.map((w) => w.coverUrl).firstWhere((c) => c != null, orElse: () => null),
      type: members.map((w) => w.type)
          .firstWhere((t) => t != ContentType.other, orElse: () => primary.type),
      publicationStatus: members.map((w) => w.publicationStatus)
          .firstWhere((s) => s != null, orElse: () => null),
      tags: {for (final w in members) ...w.tags}.toList(),
      year: members.map((w) => w.year).firstWhere((y) => y != null, orElse: () => null),
      authors: {for (final w in members) ...w.authors}.toList(),
      languages: languages.toList(),
      longStrip: members.any((w) => w.longStrip),
      links: links.values.toList(),
      lastChapter: primary.lastChapter,
    );
  }
}

/// Unified Discovery Engine: concurrent but bounded multi-source search,
/// normalisation, conservative grouping. Metadata only — never pages.
class DiscoveryEngine {
  DiscoveryEngine({required this.log, this.maxConcurrent = 4,
    this.timeout = const Duration(seconds: 12)});

  final EngineLog log;
  final int maxConcurrent;
  final Duration timeout;

  static const _comics = {ContentType.manga, ContentType.manhwa, ContentType.manhua,
    ContentType.webtoon};

  static bool _sameFamily(ContentType a, ContentType b) {
    if (a == b) return true;
    // Directory sites do not say whether a comic is manga, manhwa or webtoon
    // ("other"): it may pair with any comic, never with a novel or an anime.
    if (a == ContentType.other) return _comics.contains(b);
    if (b == ContentType.other) return _comics.contains(a);
    // Sites label the same comic manga / manhwa / webtoon.
    return _comics.contains(a) && _comics.contains(b);
  }

  static Set<String> _people(WorkInfo w) => {
        for (final a in w.authors)
          if (TitleNormalizer.normalize(a).isNotEmpty) TitleNormalizer.normalize(a),
      };

  /// Decides whether two results are the same edition of the same work.
  /// Similar-looking titles are NOT enough: only an identical distinctive
  /// alias (or a shared stable identifier) with no contradicting metadata.
  static MatchReason match(WorkInfo a, WorkInfo b) {
    if (!_sameFamily(a.type, b.type)) return MatchReason.none;
    // Same source + same work id => same work.
    for (final la in a.links) {
      for (final lb in b.links) {
        if (la.sourceId == lb.sourceId && la.workId == lb.workId) {
          return MatchReason.stableId;
        }
      }
    }
    final aliasesA = TitleNormalizer.aliases(a);
    final shared = TitleNormalizer.aliases(b).any(aliasesA.contains);
    if (!shared) return MatchReason.none;
    // Contradictions: different authors (both known) or years far apart.
    final pa = _people(a);
    final pb = _people(b);
    if (pa.isNotEmpty && pb.isNotEmpty && !pa.any(pb.contains)) return MatchReason.none;
    final ya = a.year;
    final yb = b.year;
    if (ya != null && yb != null && (ya - yb).abs() > 1) return MatchReason.none;
    return MatchReason.exactAlias;
  }

  List<WorkCluster> group(Iterable<WorkInfo> results) {
    final clusters = <WorkCluster>[];
    for (final w in results) {
      WorkCluster? target;
      MatchReason best = MatchReason.none;
      for (final c in clusters) {
        for (final m in c.members) {
          final r = match(m, w);
          if (r != MatchReason.none) {
            target = c;
            best = r;
            break;
          }
        }
        if (target != null) break;
      }
      if (target == null) {
        clusters.add(WorkCluster(w));
      } else {
        target.members.add(w);
        if (target.reason == MatchReason.none || best == MatchReason.stableId) {
          target.reason = best;
        }
      }
    }
    return clusters;
  }

  /// Searches [sources] with at most [maxConcurrent] requests in flight.
  /// Failures are reported per source in [failures], never hidden as
  /// "0 result".
  Future<List<WorkCluster>> search(String query, List<ContentSource> sources, {
    required List<String> languages,
    Map<String, String>? failures,
    int perSourceLimit = 20,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final relevant = sources.where((s) =>
        s.languages.isEmpty || s.languages.any(languages.contains)).toList();
    final found = <WorkInfo>[];
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < relevant.length) {
        final source = relevant[cursor++];
        final watch = Stopwatch()..start();
        try {
          final r = await source.search(q, limit: perSourceLimit).timeout(timeout);
          found.addAll(r);
          log.info('search', sourceId: source.id, elapsed: watch.elapsed,
              data: {'results': r.length});
        } catch (e) {
          failures?[source.id] = '$e';
          log.warn('search_failed', sourceId: source.id, message: '$e',
              elapsed: watch.elapsed);
        }
      }
    }
    final workers = relevant.isEmpty ? 0 : maxConcurrent.clamp(1, relevant.length).toInt();
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return group(found);
  }
}
