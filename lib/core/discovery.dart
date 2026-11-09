import '../engine/discovery/discovery_engine.dart';
import 'models.dart';

/// Merge the same clearly identified work returned by independent connectors.
/// Conservative: the content family must match (manga ≠ manhwa/webtoon ≠
/// manhua ≠ novel ≠ anime) AND a distinctive title or alternative title must
/// be identical after normalisation, with no contradicting author/year.
/// Engine 2.0: delegates to [DiscoveryEngine.match].
String discoveryKey(WorkInfo work) {
  final normalized = TitleNormalizer.normalize(work.title);
  return '${_family(work.type)}:$normalized';
}

String _family(ContentType type) => (type == ContentType.manhwa ||
        type == ContentType.webtoon)
    ? 'manhwa_webtoon' : type.name;

List<WorkInfo> mergeSearchResults(Iterable<WorkInfo> found) {
  // Indexed by alias and by (source, id): each result is only compared with
  // the few clusters sharing a title, instead of every cluster (thousands of
  // works from 200 sites froze the interface with the quadratic version).
  final clusters = <WorkCluster>[];
  final byAlias = <String, List<int>>{};
  final byLink = <String, int>{};
  for (final next in found) {
    final aliases = TitleNormalizer.aliases(next);
    if (TitleNormalizer.normalize(next.title).isEmpty) continue;
    final candidates = <int>{
      for (final l in next.links)
        if (byLink['${l.sourceId}|${l.workId}'] case final int i) i,
      for (final a in aliases) ...?byAlias[a],
    }.toList()
      ..sort();
    int? target;
    final fb = _family(next.type);
    for (final i in candidates) {
      final cluster = clusters[i];
      final fa = _family(cluster.primary.type);
      // "other" = comic of unknown kind (directory sites): may join any comic.
      if (fa != fb && fa != 'other' && fb != 'other') continue;
      if (cluster.members.any((m) => DiscoveryEngine.match(m, next) != MatchReason.none)) {
        target = i;
        break;
      }
    }
    final index = target ?? clusters.length;
    if (target == null) {
      clusters.add(WorkCluster(next));
    } else {
      clusters[target].members.add(next);
    }
    for (final a in aliases) {
      final list = byAlias.putIfAbsent(a, () => []);
      if (!list.contains(index)) list.add(index);
    }
    for (final l in next.links) {
      byLink.putIfAbsent('${l.sourceId}|${l.workId}', () => index);
    }
  }
  return [for (final c in clusters) c.members.length == 1 ? c.primary : c.merged];
}

/// Only auto-link two results if they share a distinctive, exact title or
/// alternative title AND their content types agree. Never merge on fuzzy
/// similarities: misidentified series could corrupt a shared reading history.
/// A manga, manhwa, manhua or webtoon label may differ between sites; a novel
/// and its comic adaptation never match.
bool sameWorkAcrossSources(WorkInfo a, WorkInfo b) =>
    DiscoveryEngine.match(a, b) != MatchReason.none;

const _titleNoise = {
  'read', 'lire', 'manga', 'manhwa', 'manhua', 'webtoon', 'comic', 'comics',
  'online', 'free', 'scan', 'scans', 'vf', 'fr', 'en', 'english', 'francais',
  'raw', 'latest', 'chapter', 'chapters', 'chapitre', 'chapitres', 'all',
  'en ligne', 'gratuit', 'series', 'serie',
};

/// The title of a site's own work page confirms the work: one of its parts
/// ("Solo Leveling - Read Manga Online" → "Solo Leveling"), once site words
/// are removed, must equal a distinctive title or alias of [work].
bool titleConfirms(WorkInfo work, String pageTitle) {
  final aliases = TitleNormalizer.aliases(work);
  if (aliases.isEmpty) return false;
  String clean(String s) => TitleNormalizer.normalize(s)
      .split(' ')
      .where((w) => w.isNotEmpty && !_titleNoise.contains(w))
      .join(' ');
  final cleanedAliases = {for (final a in aliases) clean(a)}..remove('');
  final parts = <String>{
    pageTitle,
    ...pageTitle.split(RegExp(r'\s[-–—|:]\s|\s[|]\s?|\s·\s')),
  };
  for (final part in parts) {
    final c = clean(part);
    if (c.length >= 3 && cleanedAliases.contains(c)) return true;
  }
  return false;
}
