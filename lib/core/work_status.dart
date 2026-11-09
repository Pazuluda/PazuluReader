/// Real publication status of a series, decided from several sources.
enum SeriesStatus { ongoing, hiatus, cancelled, completed, unknown }

extension SeriesStatusLabel on SeriesStatus {
  String get label => switch (this) {
        SeriesStatus.ongoing => 'En cours',
        SeriesStatus.hiatus => 'En pause',
        SeriesStatus.cancelled => 'Annulé',
        SeriesStatus.completed => 'Terminé',
        SeriesStatus.unknown => 'Statut inconnu',
      };

  /// Shown in the weekly planning.
  bool get active => this == SeriesStatus.ongoing || this == SeriesStatus.unknown;
}

/// One opinion on the status (AniList, MangaDex, a site's work page…).
class StatusVote {
  const StatusVote(this.source, this.status, this.weight);

  final String source;
  final SeriesStatus status;

  /// Databases (AniList, MangaDex) weigh more than a scan site's label,
  /// often left on « OnGoing » for years.
  final int weight;
}

class SeriesStatusDecision {
  const SeriesStatusDecision(this.status, this.reason);

  final SeriesStatus status;
  final String reason;
}

/// Status engine: explicit statuses from several sources, then the real
/// activity (date of the last chapter released anywhere).
class WorkStatusEngine {
  /// Without any chapter for this long, a series « en cours » is in fact
  /// paused (most weekly / monthly series release well within it).
  static const Duration inactiveAfter = Duration(days: 100);

  /// Without any chapter for this long, it is considered dropped.
  static const Duration deadAfter = Duration(days: 540);

  /// « OnGoing », « En cours », « RELEASING », « Hiatus », « Dropped »,
  /// « Axed », « Completed », « Terminé »… (FR / EN, any case).
  static SeriesStatus parse(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s.isEmpty) return SeriesStatus.unknown;
    if (RegExp(r'cancel|annul|drop|axed|abandon|discontinu|stopp').hasMatch(s)) {
      return SeriesStatus.cancelled;
    }
    if (RegExp(r'hiatus|pause|on hold|suspend').hasMatch(s)) return SeriesStatus.hiatus;
    if (RegExp(r'complet|termin|finish|ended|^end$|fini|achev').hasMatch(s)) {
      return SeriesStatus.completed;
    }
    if (RegExp(r'ongoing|on going|releasing|en cours|publishing|serializ|updating|'
            r'continu|in progress')
        .hasMatch(s)) {
      return SeriesStatus.ongoing;
    }
    return SeriesStatus.unknown;
  }

  /// A chapter released this recently means the series is publishing
  /// again, whatever a database still says (« hiatus », « axed »).
  static const Duration freshRelease = Duration(days: 30);

  static SeriesStatusDecision decide(List<StatusVote> votes, {
    DateTime? lastRelease,
    DateTime? now,
    bool lastReleaseIsNewest = true,
  }) {
    final at = now ?? DateTime.now();
    final score = <SeriesStatus, int>{};
    for (final v in votes) {
      if (v.status == SeriesStatus.unknown) continue;
      score[v.status] = (score[v.status] ?? 0) + v.weight;
    }
    var status = SeriesStatus.unknown;
    var best = 0;
    // On equal weight the « final » statuses win: a series can stay marked
    // « ongoing » on a site long after it ended, never the reverse.
    for (final s in const [SeriesStatus.completed, SeriesStatus.cancelled,
        SeriesStatus.hiatus, SeriesStatus.ongoing]) {
      final v = score[s] ?? 0;
      if (v > best) {
        best = v;
        status = s;
      }
    }
    final sources = [for (final v in votes) if (v.status == status) v.source].toSet().join(', ');
    if (lastRelease != null &&
        (status == SeriesStatus.hiatus || status == SeriesStatus.cancelled) &&
        at.difference(lastRelease) <= freshRelease) {
      final days = at.difference(lastRelease).inDays;
      return SeriesStatusDecision(SeriesStatus.ongoing,
          'reprise : chapitre sorti il y a ${days <= 0 ? 'moins d\'un jour' : '$days j'} '
          '($sources disait ${status.label.toLowerCase()})');
    }
    // Inactivity only counts when the date is the one of the newest chapter.
    if (lastRelease != null && lastReleaseIsNewest &&
        (status == SeriesStatus.ongoing || status == SeriesStatus.unknown)) {
      final idle = at.difference(lastRelease);
      if (idle > deadAfter) {
        return SeriesStatusDecision(SeriesStatus.cancelled,
            'aucun chapitre depuis ${idle.inDays ~/ 30} mois');
      }
      if (idle > inactiveAfter) {
        return SeriesStatusDecision(SeriesStatus.hiatus,
            'aucun chapitre depuis ${idle.inDays} jours');
      }
      if (status == SeriesStatus.unknown) {
        return const SeriesStatusDecision(SeriesStatus.ongoing, 'chapitres récents');
      }
    }
    return SeriesStatusDecision(status,
        status == SeriesStatus.unknown ? 'aucune source' : 'selon $sources');
  }
}
