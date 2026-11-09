import 'anime/anilist.dart';
import 'models.dart';

/// What the planning knows about the next release.
enum ReleaseState {
  /// Estimated from the real rhythm (manga, webtoon…).
  expected,

  /// Announced with an exact time (anime broadcast schedule).
  announced,

  /// Estimated date passed recently.
  late,

  /// No release for 1 to 4 usual intervals: probably a break.
  pauseLikely,

  /// Announced by the source, or no release for a long time.
  hiatus,

  /// First releases after a long break.
  resumed,

  /// A new season / sequel is announced.
  newSeason,

  /// Seen at a source (confirmed).
  confirmed,
}

extension ReleaseStateLabel on ReleaseState {
  String get label => switch (this) {
        ReleaseState.expected => 'Estimée',
        ReleaseState.announced => 'Annoncée',
        ReleaseState.late => 'En retard',
        ReleaseState.pauseLikely => 'Pause probable',
        ReleaseState.hiatus => 'Hiatus',
        ReleaseState.resumed => 'Reprise',
        ReleaseState.newSeason => 'Nouvelle saison',
        ReleaseState.confirmed => 'Sortie',
      };
}

/// One release, confirmed (seen at a source) or estimated (from the rhythm).
class PlannedRelease {
  const PlannedRelease({
    required this.entry,
    required this.lang,
    required this.date,
    required this.confirmed,
    this.chapterLabel,
    this.interval,
    this.isLate = false,
    this.samples = 0,
    this.state = ReleaseState.expected,
    this.timeKnown = false,
    this.note,
    this.isAnime = false,
    this.dateKnown = true,
  });

  final ReleaseState state;

  /// The hour is meaningful (exact broadcast or a very regular release hour).
  final bool timeKnown;

  /// False for a sequel announced without date.
  final bool dateKnown;
  final String? note;
  final bool isAnime;

  final LibraryEntry entry;
  final String lang;
  final DateTime date;

  /// true = observed at a source; false = estimation (never a promise).
  final bool confirmed;
  final String? chapterLabel;

  /// Median gap between the last releases (estimations only).
  final Duration? interval;

  /// The estimated date has passed without a release being observed.
  final bool isLate;
  final int samples;
}

/// Pure planning computations (testable, no I/O).
class ReleasePlanner {
  const ReleasePlanner._();

  /// Keeps release dates ordered (newest first), de-duplicated per day and
  /// bounded, so one bulk upload does not count as many releases.
  static List<String> addDates(List<String> existing, Iterable<DateTime> dates,
      {int keep = 16}) {
    final days = <String, DateTime>{};
    for (final raw in existing) {
      final d = DateTime.tryParse(raw);
      if (d != null) days[_day(d)] = d;
    }
    for (final d in dates) {
      days.putIfAbsent(_day(d), () => d);
    }
    final sorted = days.values.toList()..sort((a, b) => b.compareTo(a));
    return [for (final d in sorted.take(keep)) d.toUtc().toIso8601String()];
  }

  static String _day(DateTime d) {
    final u = d.toLocal();
    return '${u.year}-${u.month}-${u.day}';
  }

  /// Median interval of the last gaps; null under 3 releases or when the
  /// rhythm is too irregular / in hiatus (gap > 120 days).
  static Duration? rhythm(List<DateTime> newestFirst) {
    if (newestFirst.length < 3) return null;
    final gaps = <int>[];
    for (var i = 0; i + 1 < newestFirst.length && gaps.length < 8; i++) {
      final g = newestFirst[i].difference(newestFirst[i + 1]).inHours;
      if (g <= 0) continue;
      if (g > 120 * 24) break; // older history before a hiatus is ignored
      gaps.add(g);
    }
    if (gaps.length < 2) return null;
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    return Duration(hours: median < 24 ? 24 : median);
  }

  /// Typical release time of day when releases are regular (spread of the
  /// hours under 3 h), else null.
  static Duration? typicalTime(List<DateTime> dates) {
    if (dates.length < 3) return null;
    final minutes = [for (final d in dates.take(8)) d.hour * 60 + d.minute]..sort();
    final q1 = minutes[minutes.length ~/ 4];
    final q3 = minutes[(minutes.length * 3) ~/ 4];
    if (q3 - q1 > 180) return null;
    // Midnight exactly usually means "date only" (no hour published).
    if (minutes.every((m) => m == 0)) return null;
    return Duration(minutes: minutes[minutes.length ~/ 2]);
  }

  /// Estimated next release per (work, language), with breaks and hiatus.
  static List<PlannedRelease> forecast(Iterable<LibraryEntry> entries, {
    required List<String> langs,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final out = <PlannedRelease>[];
    for (final e in entries) {
      if (!e.watch || e.work.type == ContentType.anime) continue;
      final status = (e.work.publicationStatus ?? '').toLowerCase();
      if (status.contains('termin') || status.contains('annul') ||
          status.contains('complet')) {
        continue;
      }
      final announcedHiatus = status.contains('pause') || status.contains('hiatus');
      for (final lang in langs) {
        final dates = [
          for (final raw in e.releaseDates[lang] ?? const <String>[])
            if (DateTime.tryParse(raw) case final DateTime d) d.toLocal(),
        ]..sort((a, b) => b.compareTo(a));
        if (dates.isEmpty) continue;
        final latest = e.latestKnown[lang];
        final nextLabel = latest == null ? null : 'Ch. ${_next(latest)}';
        if (announcedHiatus) {
          out.add(PlannedRelease(entry: e, lang: lang, date: dates.first, confirmed: false,
              state: ReleaseState.hiatus, chapterLabel: nextLabel, dateKnown: false,
              note: 'Hiatus annoncé par la source · dernière sortie le ${_dayLabel(dates.first)}'));
          continue;
        }
        // A long gap before the latest release = the series came back.
        var interval = rhythm(dates);
        var resumedAfter = Duration.zero;
        if (dates.length >= 2) {
          final older = rhythm(dates.skip(1).toList());
          final lastGap = dates[0].difference(dates[1]);
          final reference = older ?? interval;
          if (reference != null && lastGap > reference * 3) {
            resumedAfter = lastGap;
            interval = older ?? interval;
          }
        }
        if (interval == null) continue;
        final time = typicalTime(dates);
        var next = dates.first.add(interval);
        if (time != null) {
          next = DateTime(next.year, next.month, next.day).add(time);
        }
        final overdue = at.difference(next);
        ReleaseState state;
        String? note;
        if (overdue.isNegative) {
          state = resumedAfter > Duration.zero ? ReleaseState.resumed : ReleaseState.expected;
          if (resumedAfter > Duration.zero) {
            note = 'Reprise après ${_weeks(resumedAfter)} de pause';
          }
        } else if (overdue <= interval) {
          state = ReleaseState.late;
          note = 'Attendue le ${_dayLabel(next)}';
        } else if (overdue <= interval * 4) {
          state = ReleaseState.pauseLikely;
          note = 'Aucune sortie depuis ${at.difference(dates.first).inDays} jours';
        } else if (at.difference(dates.first) < const Duration(days: 400)) {
          state = ReleaseState.hiatus;
          note = 'Hiatus probable · dernière sortie le ${_dayLabel(dates.first)}';
        } else {
          continue;
        }
        out.add(PlannedRelease(
          entry: e,
          lang: lang,
          date: next,
          confirmed: false,
          interval: interval,
          isLate: state == ReleaseState.late,
          samples: dates.length,
          chapterLabel: nextLabel,
          state: state,
          timeKnown: time != null,
          dateKnown: state != ReleaseState.pauseLikely && state != ReleaseState.hiatus,
          note: note,
        ));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Anime: exact broadcast times, breaks inside the schedule, hiatus and
  /// announced new seasons (AniList data).
  static List<PlannedRelease> animePlanning(Iterable<LibraryEntry> entries,
      Map<int, AnimeInfo> infos, List<AnimeAiring> airings, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final out = <PlannedRelease>[];
    for (final e in entries) {
      if (e.work.type != ContentType.anime) continue;
      final id = AniListClient.idOf(e.work);
      final info = id == null ? null : infos[id];
      if (id == null || info == null) continue;
      final mine = airings.where((a) => a.mediaId == id).toList()
        ..sort((a, b) => a.airingAt.compareTo(b.airingAt));
      DateTime? previous;
      for (final a in mine) {
        final p = previous;
        previous = a.airingAt;
        if (a.airingAt.isBefore(at)) continue;
        final gap = p == null ? null : a.airingAt.difference(p);
        final isBreak = gap != null && gap > const Duration(days: 10);
        out.add(PlannedRelease(
          entry: e,
          lang: 'anime',
          date: a.airingAt,
          confirmed: false,
          isAnime: true,
          timeKnown: true,
          state: isBreak ? ReleaseState.resumed : ReleaseState.announced,
          chapterLabel: 'Épisode ${a.episode}',
          note: isBreak ? 'Reprise après ${_weeks(gap)} de pause' : null,
        ));
      }
      if (info.status == 'HIATUS') {
        out.add(PlannedRelease(entry: e, lang: 'anime', date: at, confirmed: false,
            isAnime: true, state: ReleaseState.hiatus, dateKnown: false,
            note: 'Diffusion en pause (hiatus annoncé)'));
      }
      if (info.status == 'NOT_YET_RELEASED' && mine.isEmpty) {
        final start = info.startDate;
        out.add(PlannedRelease(entry: e, lang: 'anime', date: start ?? at, confirmed: false,
            isAnime: true, state: ReleaseState.newSeason, dateKnown: start != null,
            chapterLabel: 'Épisode 1',
            note: start == null ? 'Début annoncé, date non communiquée'
                : 'Début de diffusion ${info.seasonLabel ?? ''}'.trim()));
      }
      for (final sequel in info.upcomingSequels) {
        final start = sequel.startDate;
        out.add(PlannedRelease(entry: e, lang: 'anime', date: start ?? at, confirmed: false,
            isAnime: true, state: ReleaseState.newSeason, dateKnown: start != null,
            chapterLabel: sequel.title,
            note: start == null
                ? 'Nouvelle saison annoncée, date non communiquée'
                : 'Nouvelle saison · ${_dayLabel(start)}'));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _weeks(Duration d) {
    final w = (d.inDays / 7).round();
    return w <= 1 ? '${d.inDays} jours' : '$w semaines';
  }

  static String _next(double latest) {
    final n = latest.floor() + 1;
    return '$n';
  }

  /// Confirmed releases of the last [days] days from the notifications.
  static List<PlannedRelease> recent(Iterable<LibraryEntry> entries,
      List<UpdateItem> updates, {required List<String> langs, int days = 14,
      DateTime? now}) {
    final at = now ?? DateTime.now();
    final byId = {for (final e in entries) e.work.id: e};
    final out = <PlannedRelease>[];
    for (final u in updates) {
      if (!langs.contains(u.lang)) continue;
      // The real publication date when the source gives it, never the
      // moment Pazulu happened to notice an old chapter.
      if (at.difference(u.releasedAt) > Duration(days: days)) continue;
      final e = byId[u.workId];
      if (e == null) continue;
      out.add(PlannedRelease(entry: e, lang: u.lang, date: u.releasedAt,
          confirmed: true, chapterLabel: u.key.label, timeKnown: u.publishedAt != null));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Unread chapters known for an entry (best effort from numbers).
  static int unreadEstimate(LibraryEntry e, List<String> langs) {
    double? latest;
    for (final l in langs) {
      final v = e.latestKnown[l];
      if (v != null && (latest == null || v > latest)) latest = v;
    }
    if (latest == null) return 0;
    final last = double.tryParse(e.progress.lastKey ?? '');
    if (last == null) return e.progress.readKeys.isEmpty ? latest.floor() : 0;
    final diff = latest.floor() - last.floor();
    return diff < 0 ? 0 : diff;
  }

  /// Works planned for [weekday] (1 = Monday).
  static List<LibraryEntry> plannedOn(Iterable<LibraryEntry> entries, int weekday) =>
      [for (final e in entries) if (e.readingDays.contains(weekday)) e]
        ..sort((a, b) => a.work.title.toLowerCase().compareTo(b.work.title.toLowerCase()));
}
