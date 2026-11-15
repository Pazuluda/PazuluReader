import 'chapter_key.dart';
import 'models.dart';
import 'site_index.dart';

/// Un passage dans l'historique de lecture.
class HistoryItem {
  HistoryItem({
    required this.workId,
    required this.title,
    required this.chapterId,
    required this.at,
    this.finished = false,
  });

  final String workId;
  final String title;
  final String chapterId;
  final DateTime at;
  bool finished;

  String get chapterLabel => ChapterKey.parse(chapterId).longLabel;

  Map<String, dynamic> toJson() => {
        'w': workId,
        't': title,
        'c': chapterId,
        'at': at.toIso8601String(),
        if (finished) 'f': true,
      };

  static HistoryItem? fromJson(Object? raw) {
    if (raw is! Map || raw['w'] is! String || raw['c'] is! String) return null;
    final at = DateTime.tryParse('${raw['at']}');
    if (at == null) return null;
    return HistoryItem(
      workId: raw['w'] as String,
      title: '${raw['t'] ?? ''}',
      chapterId: raw['c'] as String,
      at: at,
      finished: raw['f'] == true,
    );
  }
}

/// Statistiques d'une œuvre, tirées de l'historique.
class WorkStats {
  const WorkStats({
    required this.readCount,
    this.firstAt,
    this.lastAt,
    this.perWeek,
    this.remaining,
    this.weeksToCatchUp,
  });

  final int readCount;
  final DateTime? firstAt;
  final DateTime? lastAt;

  /// Chapitres terminés par semaine (8 dernières semaines), null si trop peu.
  final double? perWeek;
  final int? remaining;
  final double? weeksToCatchUp;
}

class LibraryInsights {
  LibraryInsights._();

  /// Lectures « en cours » pas ouvertes depuis [after] (90 jours) :
  /// proposées en pause.
  static List<LibraryEntry> stale(Iterable<LibraryEntry> entries,
      {DateTime? now, Duration after = const Duration(days: 90)}) {
    final at = now ?? DateTime.now();
    return [
      for (final e in entries)
        if (e.status == TrackStatus.reading &&
            at.difference(e.progress.updatedAt ?? e.addedAt) > after)
          e,
    ];
  }

  /// Paires d'œuvres de la bibliothèque qui sont probablement la même
  /// (même titre ou titre alternatif, écrit un peu autrement). Calcul en
  /// une passe (pas de comparaison de chaque paire).
  static List<(LibraryEntry, LibraryEntry)> duplicates(Iterable<LibraryEntry> entries,
      {Set<String> ignored = const {}}) {
    final byKey = <String, List<LibraryEntry>>{};
    for (final e in entries) {
      if (e.work.type == ContentType.anime) continue;
      final keys = <String>{
        for (final t in [e.work.title, ...e.work.altTitles])
          SiteTitleIndex.loose(SiteTitleIndex.norm(t)),
      }..removeWhere((k) => k.length < 6);
      for (final k in keys) {
        byKey.putIfAbsent(k, () => []).add(e);
      }
    }
    final seen = <String>{};
    final out = <(LibraryEntry, LibraryEntry)>[];
    for (final list in byKey.values) {
      if (list.length < 2) continue;
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i], b = list[j];
          if (a.work.id == b.work.id) continue;
          final id = pairId(a.work.id, b.work.id);
          if (ignored.contains(id) || !seen.add(id)) continue;
          out.add((a, b));
        }
      }
    }
    return out;
  }

  static String pairId(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  static WorkStats statsFor(LibraryEntry e, Iterable<HistoryItem> history,
      {double? latest, DateTime? now}) {
    final at = now ?? DateTime.now();
    final mine = [for (final h in history) if (h.workId == e.work.id) h];
    DateTime? first, last;
    for (final h in mine) {
      if (first == null || h.at.isBefore(first)) first = h.at;
      if (last == null || h.at.isAfter(last)) last = h.at;
    }
    final since = at.subtract(const Duration(days: 56));
    final recentDone = mine.where((h) => h.finished && h.at.isAfter(since)).length;
    final perWeek = recentDone >= 3 ? recentDone / 8 : null;
    final current = e.progress.lastKey == null ? null : ChapterKey.parse(e.progress.lastKey).number;
    final remaining = latest == null
        ? null
        : (latest - (current ?? 0)).floor().clamp(0, 100000).toInt();
    return WorkStats(
      readCount: e.progress.readKeys.length,
      firstAt: first ?? (e.progress.readKeys.isEmpty ? null : e.addedAt),
      lastAt: last ?? e.progress.updatedAt,
      perWeek: perWeek,
      remaining: remaining,
      weeksToCatchUp: perWeek == null || remaining == null || remaining == 0 ? null : remaining / perWeek,
    );
  }
}
