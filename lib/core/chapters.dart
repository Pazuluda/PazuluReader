import 'chapter_key.dart';
import 'models.dart';

/// Toutes les versions disponibles d'un même chapitre canonique.
class ChapterGroup {
  ChapterGroup(this.key, this.variants);

  final ChapterKey key;
  final List<SourceChapter> variants;

  Set<String> get languages => variants.map((v) => v.lang).toSet();

  String? get title {
    for (final v in variants) {
      final t = v.title;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    }
    return null;
  }

  /// First publication of the chapter, whatever the source or language.
  DateTime? get firstDate {
    DateTime? best;
    for (final v in variants) {
      final d = v.publishedAt;
      if (d != null && (best == null || d.isBefore(best))) best = d;
    }
    return best;
  }

  DateTime? get latestDate {
    DateTime? best;
    for (final v in variants) {
      final d = v.publishedAt;
      if (d != null && (best == null || d.isAfter(best))) best = d;
    }
    return best;
  }
}

/// Regroupe les chapitres de toutes les sources par clé canonique,
/// triés par ordre croissant. Les doublons stricts (même source, même id)
/// sont éliminés.
List<ChapterGroup> groupChapters(Iterable<SourceChapter> chapters) {
  final byKey = <ChapterKey, List<SourceChapter>>{};
  final seen = <String>{};
  for (final c in chapters) {
    if (!seen.add('${c.sourceId}:${c.chapterId}')) continue;
    byKey.putIfAbsent(c.key, () => <SourceChapter>[]).add(c);
  }
  final keys = byKey.keys.toList()..sort();
  return [for (final k in keys) ChapterGroup(k, byKey[k]!)];
}

/// Ordonne les versions d'un chapitre : la première est le « Lecteur 1 ».
///
/// Ordre : lecteur choisi par défaut, puis langue préférée, puis source
/// préférée, puis version la plus récente. Les liens externes passent en
/// dernier.
List<SourceChapter> rankVariants(
  List<SourceChapter> variants, {
  required List<String> langs,
  String? preferredLang,
  String? preferredGroup,
  String? preferredSourceId,
}) {
  int langRank(String lang) {
    if (preferredLang != null && lang == preferredLang) return -1;
    final i = langs.indexOf(lang);
    return i < 0 ? 99 : i;
  }

  final list = [...variants];
  list.sort((a, b) {
    if (a.isExternal != b.isExternal) return a.isExternal ? 1 : -1;

    if (preferredGroup != null) {
      final aPref = a.group == preferredGroup &&
          (preferredLang == null || a.lang == preferredLang);
      final bPref = b.group == preferredGroup &&
          (preferredLang == null || b.lang == preferredLang);
      if (aPref != bPref) return aPref ? -1 : 1;
    }

    final byLang = langRank(a.lang).compareTo(langRank(b.lang));
    if (byLang != 0) return byLang;

    if (preferredSourceId != null) {
      final aSrc = a.sourceId == preferredSourceId;
      final bSrc = b.sourceId == preferredSourceId;
      if (aSrc != bSrc) return aSrc ? -1 : 1;
    }

    final ad = a.publishedAt;
    final bd = b.publishedAt;
    if (ad != null && bd != null) return bd.compareTo(ad);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return 0;
  });
  return list;
}

/// Plage de chapitres entiers absents dans une langue.
class MissingRange {
  const MissingRange(this.from, this.to);

  final int from;
  final int to;

  @override
  String toString() => from == to ? '$from' : '$from–$to';
}

/// Chapitres disponibles dans d'autres langues mais pas dans [lang].
/// Ne renvoie rien si la langue n'a aucun chapitre.
List<MissingRange> missingInLanguage(List<ChapterGroup> groups, String lang) {
  final inLang = <int>{};
  final anywhere = <int>{};
  for (final g in groups) {
    final n = g.key.number;
    if (n == null) continue;
    final whole = n.floor();
    anywhere.add(whole);
    if (g.languages.contains(lang)) inLang.add(whole);
  }
  if (inLang.isEmpty) return const [];

  final missing = (anywhere.difference(inLang).toList()..sort());
  final ranges = <MissingRange>[];
  for (final n in missing) {
    if (ranges.isNotEmpty && ranges.last.to == n - 1) {
      ranges[ranges.length - 1] = MissingRange(ranges.last.from, n);
    } else {
      ranges.add(MissingRange(n, n));
    }
  }
  return ranges;
}

/// Indice du chapitre à ouvrir pour « Reprendre ».
/// Retourne (indice, page de départ).
(int, int) resumePosition(List<ChapterGroup> groups, ReadingProgress p) {
  if (groups.isEmpty) return (0, 0);
  final last = p.lastKey;
  if (last == null) {
    // Premier chapitre non lu.
    final i = groups.indexWhere((g) => !p.readKeys.contains(g.key.id));
    return (i < 0 ? 0 : i, 0);
  }
  final i = groups.indexWhere((g) => g.key.id == last);
  if (i < 0) {
    // The previous source may have disappeared. Resume at the nearest
    // available chapter, rather than restarting an old series at chapter 1.
    final previous = ChapterKey.parse(last);
    final next = groups.indexWhere((g) => g.key.compareTo(previous) >= 0);
    return (next < 0 ? groups.length - 1 : next, 0);
  }
  if (p.readKeys.contains(last) && i + 1 < groups.length) {
    return (i + 1, 0);
  }
  return (i, p.lastPage);
}
