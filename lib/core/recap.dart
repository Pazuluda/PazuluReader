import 'achievements.dart';
import 'library_insights.dart';
import 'models.dart';

/// Un défi du mois (progression / objectif).
class MonthlyChallenge {
  const MonthlyChallenge(this.title, this.value, this.goal);

  final String title;
  final int value;
  final int goal;

  bool get done => value >= goal;
  double get ratio => goal == 0 ? 1 : (value / goal).clamp(0, 1).toDouble();
}

/// Le récap d'une année, façon « Wrapped ».
class YearRecap {
  const YearRecap({
    required this.year,
    required this.chapters,
    required this.minutes,
    required this.activeDays,
    required this.bestStreak,
    required this.bestMonth,
    required this.bestMonthCount,
    required this.topWorks,
    required this.topGenre,
    required this.newWorks,
    required this.finishedSeries,
  });

  final int year;
  final int chapters;
  final int minutes;
  final int activeDays;
  final int bestStreak;
  final int bestMonth; // 1–12, 0 = aucun
  final int bestMonthCount;
  final List<(String, int)> topWorks;
  final String? topGenre;
  final int newWorks;
  final int finishedSeries;
}

class Recap {
  Recap._();

  static DateTime? _day(String key) => DateTime.tryParse(key);

  /// Trois défis du mois en cours.
  static List<MonthlyChallenge> challenges(Iterable<LibraryEntry> entries, ActivityLog log,
      Iterable<HistoryItem> history, {DateTime? now}) {
    final at = now ?? DateTime.now();
    bool thisMonth(DateTime d) => d.year == at.year && d.month == at.month;
    var chapters = 0, days = 0;
    for (final e in log.days.entries) {
      final d = _day(e.key);
      if (d == null || !thisMonth(d)) continue;
      chapters += e.value.chapters;
      if (e.value.chapters + e.value.episodes > 0) days++;
    }
    // Œuvres commencées ce mois-ci : premier passage dans l'historique.
    final firstSeen = <String, DateTime>{};
    for (final h in history) {
      final old = firstSeen[h.workId];
      if (old == null || h.at.isBefore(old)) firstSeen[h.workId] = h.at;
    }
    final started = firstSeen.values.where(thisMonth).length;
    final finished = entries
        .where((e) => e.status == TrackStatus.completed && thisMonth(e.updatedAt))
        .length;
    return [
      MonthlyChallenge('Lire 100 chapitres ce mois-ci', chapters, 100),
      MonthlyChallenge('Lire 15 jours différents', days, 15),
      MonthlyChallenge('Commencer 3 nouvelles œuvres', started, 3),
      MonthlyChallenge('Terminer une série', finished, 1),
    ];
  }

  static YearRecap year(Iterable<LibraryEntry> entries, ActivityLog log, Iterable<HistoryItem> history,
      {required int year}) {
    var chapters = 0, minutes = 0, activeDays = 0;
    final perMonth = List<int>.filled(13, 0);
    final active = <DateTime>[];
    for (final e in log.days.entries) {
      final d = _day(e.key);
      if (d == null || d.year != year) continue;
      chapters += e.value.chapters;
      minutes += e.value.minutes;
      final n = e.value.chapters + e.value.episodes;
      perMonth[d.month] += n;
      if (n > 0) {
        activeDays++;
        active.add(DateTime(d.year, d.month, d.day));
      }
    }
    active.sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in active) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    var bestMonth = 0;
    for (var m = 1; m <= 12; m++) {
      if (perMonth[m] > (bestMonth == 0 ? 0 : perMonth[bestMonth])) bestMonth = m;
    }
    final byWork = <String, int>{};
    final titles = <String, String>{};
    final firstSeen = <String, DateTime>{};
    for (final h in history) {
      final old = firstSeen[h.workId];
      if (old == null || h.at.isBefore(old)) firstSeen[h.workId] = h.at;
      if (h.at.year != year || !h.finished) continue;
      byWork[h.workId] = (byWork[h.workId] ?? 0) + 1;
      titles[h.workId] = h.title;
    }
    final top = byWork.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final byId = {for (final e in entries) e.work.id: e};
    final genres = <String, int>{};
    for (final t in top.take(10)) {
      for (final g in byId[t.key]?.work.tags ?? const <String>[]) {
        if (g.startsWith('★')) continue;
        genres[g] = (genres[g] ?? 0) + t.value;
      }
    }
    final topGenre = genres.isEmpty
        ? null
        : (genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    return YearRecap(
      year: year,
      chapters: chapters,
      minutes: minutes,
      activeDays: activeDays,
      bestStreak: best,
      bestMonth: bestMonth,
      bestMonthCount: bestMonth == 0 ? 0 : perMonth[bestMonth],
      topWorks: [
        for (final t in top.take(5)) (byId[t.key]?.work.title ?? titles[t.key] ?? t.key, t.value),
      ],
      topGenre: topGenre,
      newWorks: firstSeen.values.where((d) => d.year == year).length,
      finishedSeries: entries.where((e) => e.status == TrackStatus.completed && e.updatedAt.year == year).length,
    );
  }
}
