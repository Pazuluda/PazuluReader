import '../../engine/discovery/discovery_engine.dart';
import '../anime/anilist.dart';
import '../models.dart';
import '../planning.dart';

enum SlotKind { anime, comic }

enum SlotState {
  /// Already out (seen at a source or broadcast time passed).
  released,

  /// Official schedule (AniList broadcast, WEBTOON update day).
  scheduled,

  /// Projected from the real rhythm of the series.
  estimated,
}

extension SlotStateLabel on SlotState {
  String get label => switch (this) {
        SlotState.released => 'Sorti',
        SlotState.scheduled => 'Prévu',
        SlotState.estimated => 'Estimé',
      };
}

/// One line of the weekly planning: a series, a day, maybe an hour.
class ScheduleSlot {
  ScheduleSlot({
    required this.kind,
    required this.title,
    required this.at,
    required this.timeKnown,
    required this.lang,
    required this.label,
    required this.state,
    required Set<String> providers,
    this.altTitles = const [],
    this.coverUrl,
    this.url,
    this.streams = const [],
    this.work,
    this.anime,
    this.note,
  }) : providers = {...providers};

  final SlotKind kind;
  final String title;
  final List<String> altTitles;
  DateTime at;
  bool timeKnown;

  /// 'en', 'fr' for chapters; 'ja' for an original broadcast.
  final String lang;
  String label;
  SlotState state;
  final Set<String> providers;
  String? coverUrl;
  final String? url;
  final List<StreamingLink> streams;

  /// Enough to open the series page (MangaDex record, site page…).
  WorkInfo? work;
  final AnimeInfo? anime;
  String? note;

  Set<String> get aliases => TitleNormalizer.aliases(
      WorkInfo(id: title, title: title, altTitles: altTitles));

  String get mergeKey {
    final l = at.toLocal();
    final a = TitleNormalizer.normalize(title);
    return '${kind.name}|$lang|$a|${l.year}-${l.month}-${l.day}';
  }
}

/// What each source of the planning returned (shown to the user).
class ScheduleReport {
  const ScheduleReport(this.name, {this.count = 0, this.error, this.group = ''});
  final String name;
  final String group;
  final int count;
  final String? error;
  bool get ok => error == null;
}

/// Release history of one series in one language, kept on disk so the
/// rhythm of every series becomes known after a few weeks of use.
class SeriesHistory {
  SeriesHistory({required this.title, required this.lang, this.coverUrl, this.url,
      this.sourceId, this.workId, List<String>? dates, this.lastLabel,
      Map<String, String>? chapterDates})
      : dates = dates ?? <String>[],
        chapterDates = chapterDates ?? <String, String>{};

  final String title;
  final String lang;
  String? coverUrl;
  String? url;
  String? sourceId;
  String? workId;
  String? lastLabel;

  /// ISO dates, newest first, one per day (ReleasePlanner.addDates).
  List<String> dates;

  /// Chapter → EARLIEST release time seen on any site's « latest updates »
  /// (the site that released it first). Last 40 chapters.
  Map<String, String> chapterDates;

  static String keyOf(String title, String lang) =>
      '${TitleNormalizer.normalize(title)}|$lang';

  Map<String, dynamic> toJson() => {
        't': title, 'l': lang,
        if (coverUrl != null) 'c': coverUrl,
        if (url != null) 'u': url,
        if (sourceId != null) 's': sourceId,
        if (workId != null) 'w': workId,
        if (lastLabel != null) 'n': lastLabel,
        'd': dates,
        if (chapterDates.isNotEmpty) 'cd': chapterDates,
      };

  static SeriesHistory? fromJson(Object? raw) {
    if (raw is! Map || raw['t'] is! String || raw['l'] is! String) return null;
    return SeriesHistory(
      title: raw['t'] as String,
      lang: raw['l'] as String,
      coverUrl: raw['c'] as String?,
      url: raw['u'] as String?,
      sourceId: raw['s'] as String?,
      workId: raw['w'] as String?,
      lastLabel: raw['n'] as String?,
      dates: [for (final d in (raw['d'] is List ? raw['d'] as List : const [])) if (d is String) d],
      chapterDates: {
        if (raw['cd'] is Map)
          for (final e in (raw['cd'] as Map).entries) '${e.key}': '${e.value}',
      },
    );
  }

  WorkInfo? toWork() {
    final s = sourceId;
    final w = workId;
    if (s == null || w == null) return null;
    return WorkInfo(id: s == 'mangadex' ? 'mangadex:$w' : '$s:$w', title: title,
        coverUrl: coverUrl, languages: [lang], links: [SourceLink(sourceId: s, workId: w)]);
  }
}

class WeeklyScheduleBuilder {
  /// Monday 00:00 (local) of the week containing [day].
  static DateTime weekStart(DateTime day) {
    final l = day.toLocal();
    final d = DateTime(l.year, l.month, l.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// Records a release in [history].
  static void record(Map<String, SeriesHistory> history, {
    required String title,
    required String lang,
    required DateTime at,
    String? coverUrl,
    String? url,
    String? sourceId,
    String? workId,
    String? label,
  }) {
    final key = SeriesHistory.keyOf(title, lang);
    if (key.startsWith('|')) return;
    final h = history.putIfAbsent(key, () => SeriesHistory(title: title, lang: lang));
    h.coverUrl ??= coverUrl;
    h.url ??= url;
    if (h.sourceId == null && sourceId != null && workId != null) {
      h.sourceId = sourceId;
      h.workId = workId;
    }
    final newest = h.dates.isEmpty ? null : DateTime.tryParse(h.dates.first);
    if (label != null && (newest == null || !at.isBefore(newest))) h.lastLabel = label;
    if (label != null) {
      final known = DateTime.tryParse(h.chapterDates[label] ?? '');
      if (known == null || at.isBefore(known)) h.chapterDates[label] = at.toIso8601String();
      if (h.chapterDates.length > 40) {
        final sorted = h.chapterDates.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        h.chapterDates = {for (final e in sorted.take(40)) e.key: e.value};
      }
    }
    h.dates = ReleasePlanner.addDates(h.dates, [at], keep: 24);
  }

  /// Interval of a series: the planner's median rhythm (3+ releases), or a
  /// weekly rhythm proven by two releases 6–8 days apart.
  static Duration? interval(List<DateTime> newestFirst) {
    final r = ReleasePlanner.rhythm(newestFirst);
    if (r != null) return r;
    if (newestFirst.length == 2) {
      final gap = newestFirst[0].difference(newestFirst[1]);
      if (gap >= const Duration(days: 6) && gap <= const Duration(days: 8)) {
        return const Duration(days: 7);
      }
    }
    return null;
  }

  /// Projected releases of the series in [history] for the week starting
  /// at [start]. Only after the last observed release; never in the past
  /// beyond « today » (a missed estimate is not shown as a release).
  static List<ScheduleSlot> project(Map<String, SeriesHistory> history, DateTime start,
      {DateTime? now}) {
    final at = now ?? DateTime.now();
    final end = start.add(const Duration(days: 7));
    final today = DateTime(at.year, at.month, at.day);
    final out = <ScheduleSlot>[];
    for (final h in history.values) {
      final dates = [
        for (final raw in h.dates)
          if (DateTime.tryParse(raw) case final DateTime d) d.toLocal(),
      ]..sort((a, b) => b.compareTo(a));
      if (dates.isEmpty) continue;
      final step = interval(dates);
      if (step == null || step > const Duration(days: 15)) continue;
      // Stale series (no release for 3 intervals) are not projected.
      if (at.difference(dates.first) > step * 3) continue;
      final time = ReleasePlanner.typicalTime(dates);
      var next = dates.first.add(step);
      for (var guard = 0; guard < 14 && next.isBefore(end); guard++) {
        var slotAt = next;
        if (time != null) slotAt = DateTime(next.year, next.month, next.day).add(time);
        final day = DateTime(slotAt.year, slotAt.month, slotAt.day);
        if (!slotAt.isBefore(start) && !day.isBefore(today)) {
          out.add(ScheduleSlot(
            kind: SlotKind.comic,
            title: h.title,
            at: slotAt,
            timeKnown: time != null,
            lang: h.lang,
            label: _nextLabel(h.lastLabel, dates.first, slotAt, step),
            state: SlotState.estimated,
            providers: {'Rythme observé'},
            coverUrl: h.coverUrl,
            url: h.url,
            work: h.toWork(),
            note: 'Environ tous les ${step.inDays} j · ${dates.length} sorties observées',
          ));
        }
        next = next.add(step);
      }
    }
    return out;
  }

  static String _nextLabel(String? last, DateTime lastAt, DateTime next, Duration step) {
    final n = double.tryParse(last ?? '');
    if (n == null) return 'Prochain chapitre';
    final ahead = (next.difference(lastAt).inHours / step.inHours).round();
    return 'Ch. ${n.floor() + (ahead < 1 ? 1 : ahead)}';
  }

  /// Merges the slots of every provider: one line per series, language and
  /// day; « released » beats « scheduled » beats « estimated »; a precise
  /// hour beats an unknown one.
  static List<ScheduleSlot> merge(Iterable<ScheduleSlot> slots) {
    final byKey = <String, ScheduleSlot>{};
    for (final s in slots) {
      final key = s.mergeKey;
      final current = byKey[key];
      if (current == null) {
        byKey[key] = s;
        continue;
      }
      current.providers.addAll(s.providers);
      current.coverUrl ??= s.coverUrl;
      current.work ??= s.work;
      if (s.state.index < current.state.index) {
        current.state = s.state;
        current.label = s.label;
        current.note = s.note ?? current.note;
        if (s.timeKnown || !current.timeKnown) {
          current.at = s.at;
          current.timeKnown = s.timeKnown;
        }
      } else if (!current.timeKnown && s.timeKnown) {
        current.at = s.at;
        current.timeKnown = true;
      }
    }
    final out = byKey.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// The series the user follows (library) — the personal planning.
  static bool followed(ScheduleSlot slot, Iterable<LibraryEntry> entries) {
    final mine = slot.aliases;
    final animeId = slot.anime?.id ?? (slot.work == null ? null : AniListClient.idOf(slot.work!));
    if (animeId != null) {
      for (final e in entries) {
        if (AniListClient.idOf(e.work) == animeId) return true;
      }
    }
    for (final e in entries) {
      if ((slot.kind == SlotKind.anime) != (e.work.type == ContentType.anime)) continue;
      if (TitleNormalizer.aliases(e.work).any(mine.contains)) return true;
    }
    return false;
  }
}
