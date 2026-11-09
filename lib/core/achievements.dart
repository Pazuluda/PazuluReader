import 'dart:math' as math;

import 'models.dart';

/// Daily activity, kept forever (a few bytes per day).
class DayActivity {
  DayActivity({this.chapters = 0, this.episodes = 0, this.minutes = 0});
  int chapters;
  int episodes;

  /// Estimated time (5 min per chapter, the episode duration for anime).
  int minutes;

  Map<String, dynamic> toJson() => {'c': chapters, 'e': episodes, 'm': minutes};

  static DayActivity fromJson(Object? raw) {
    if (raw is! Map) return DayActivity();
    int n(Object? v) => v is int ? v : 0;
    return DayActivity(chapters: n(raw['c']), episodes: n(raw['e']), minutes: n(raw['m']));
  }
}

/// Activity journal + unlocked achievements (stored with the library).
class ActivityLog {
  ActivityLog({Map<String, DayActivity>? days, Map<String, String>? unlocked})
      : days = days ?? <String, DayActivity>{},
        unlocked = unlocked ?? <String, String>{};

  /// 'yyyy-mm-dd' → activity.
  final Map<String, DayActivity> days;

  /// Achievement id → ISO date of unlocking.
  final Map<String, String> unlocked;

  static String dayKey(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  DayActivity _today(DateTime? at) =>
      days.putIfAbsent(dayKey(at ?? DateTime.now()), DayActivity.new);

  void addChapters(int count, {DateTime? at}) {
    if (count <= 0) return;
    final d = _today(at);
    d.chapters += count;
    d.minutes += 5 * count;
  }

  void addEpisodes(int count, {int minutesEach = 24, DateTime? at}) {
    if (count <= 0) return;
    final d = _today(at);
    d.episodes += count;
    d.minutes += minutesEach * count;
  }

  Map<String, dynamic> toJson() => {
        'days': {for (final e in days.entries) e.key: e.value.toJson()},
        'unlocked': unlocked,
      };

  static ActivityLog fromJson(Object? raw) {
    if (raw is! Map) return ActivityLog();
    final days = <String, DayActivity>{};
    final d = raw['days'];
    if (d is Map) {
      for (final e in d.entries) {
        if (e.key is String) days[e.key as String] = DayActivity.fromJson(e.value);
      }
    }
    final u = raw['unlocked'];
    return ActivityLog(days: days, unlocked: {
      if (u is Map)
        for (final e in u.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    });
  }

  /// Merge (restoring a backup): the larger value of each day is kept.
  void mergeFrom(ActivityLog other) {
    for (final e in other.days.entries) {
      final mine = days[e.key];
      if (mine == null) {
        days[e.key] = e.value;
      } else {
        mine.chapters = math.max(mine.chapters, e.value.chapters);
        mine.episodes = math.max(mine.episodes, e.value.episodes);
        mine.minutes = math.max(mine.minutes, e.value.minutes);
      }
    }
    for (final e in other.unlocked.entries) {
      unlocked.putIfAbsent(e.key, () => e.value);
    }
  }
}

/// Everything the profile shows, computed from the library and the journal.
class ReaderStats {
  ReaderStats({
    required this.chapters,
    required this.episodes,
    required this.completed,
    required this.library,
    required this.favorites,
    required this.animeCount,
    required this.types,
    required this.currentStreak,
    required this.bestStreak,
    required this.bestDay,
    required this.year,
    required this.yearChapters,
    required this.yearEpisodes,
    required this.yearMinutes,
    required this.months,
    required this.topGenres,
    required this.topWork,
    required this.activeDays,
    this.weekChapters = 0,
    this.monthChapters = 0,
    this.totalMinutes = 0,
    this.bestMonth = 0,
    this.rated = 0,
    this.topWorkChapters = 0,
    this.langsRead = 0,
    this.genresCount = 0,
    this.mangaCount = 0,
    this.manhwaCount = 0,
    this.manhuaCount = 0,
    this.noted = 0,
  });

  /// Chapters (and episodes) of the last 7 days / this calendar month.
  final int weekChapters;
  final int monthChapters;

  /// Estimated time since the journal exists (5 min per chapter).
  final int totalMinutes;

  /// Most chapters + episodes in one calendar month.
  final int bestMonth;
  final int rated;
  final int topWorkChapters;

  /// Languages read (EN, FR…).
  final int langsRead;
  final int genresCount;
  final int mangaCount;
  final int manhwaCount;
  final int manhuaCount;
  final int noted;

  final int chapters;
  final int episodes;
  final int completed;
  final int library;
  final int favorites;
  final int animeCount;
  final Set<ContentType> types;
  final int currentStreak;
  final int bestStreak;
  final int bestDay;
  final int year;
  final int yearChapters;
  final int yearEpisodes;
  final int yearMinutes;

  /// Chapters + episodes per month of [year] (index 0 = January).
  final List<int> months;
  final List<MapEntry<String, int>> topGenres;
  final LibraryEntry? topWork;
  final int activeDays;

  int get xp => chapters * 10 + episodes * 30 + completed * 150 + favorites * 5;

  static ReaderStats compute(Iterable<LibraryEntry> entries, ActivityLog log, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final list = entries.toList();
    final comics = list.where((e) => e.work.type != ContentType.anime).toList();
    final anime = list.where((e) => e.work.type == ContentType.anime).toList();
    // Totals come from the library itself (includes reading done before the
    // journal existed), never below what the journal recorded.
    var chapters = comics.fold<int>(0, (n, e) => n + e.progress.readKeys.length);
    var episodes = anime.fold<int>(0, (n, e) => n + e.episodesWatched);
    final logged = log.days.values;
    chapters = math.max(chapters, logged.fold<int>(0, (n, d) => n + d.chapters));
    episodes = math.max(episodes, logged.fold<int>(0, (n, d) => n + d.episodes));

    // Streaks of consecutive active days.
    final active = <DateTime>[
      for (final e in log.days.entries)
        if (e.value.chapters + e.value.episodes > 0)
          if (DateTime.tryParse(e.key) case final DateTime d) d,
    ]..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in active) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      best = math.max(best, run);
      prev = d;
    }
    final today = DateTime(at.year, at.month, at.day);
    var current = 0;
    if (prev != null && today.difference(prev).inDays <= 1) current = run;

    final months = List<int>.filled(12, 0);
    var yc = 0, ye = 0, ym = 0, bestDay = 0;
    for (final e in log.days.entries) {
      final d = DateTime.tryParse(e.key);
      if (d == null) continue;
      bestDay = math.max(bestDay, e.value.chapters + e.value.episodes);
      if (d.year != at.year) continue;
      months[d.month - 1] += e.value.chapters + e.value.episodes;
      yc += e.value.chapters;
      ye += e.value.episodes;
      ym += e.value.minutes;
    }

    final genres = <String, int>{};
    for (final e in list) {
      final weight = 1 + e.progress.readKeys.length + e.episodesWatched;
      for (final t in e.work.tags) {
        if (t.startsWith('★')) continue;
        genres[t] = (genres[t] ?? 0) + weight;
      }
    }
    final top = genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    LibraryEntry? topWork;
    for (final e in list) {
      final score = e.progress.readKeys.length + e.episodesWatched;
      final bestScore = topWork == null ? -1
          : topWork.progress.readKeys.length + topWork.episodesWatched;
      if (score > 0 && score > bestScore) topWork = e;
    }

    final weekStart = today.subtract(const Duration(days: 6));
    var week = 0, month = 0, total = 0;
    final perMonth = <String, int>{};
    for (final e in log.days.entries) {
      final d = DateTime.tryParse(e.key);
      if (d == null) continue;
      final n = e.value.chapters + e.value.episodes;
      total += e.value.minutes;
      if (!d.isBefore(weekStart)) week += n;
      if (d.year == at.year && d.month == at.month) month += n;
      final m = '${d.year}-${d.month}';
      perMonth[m] = (perMonth[m] ?? 0) + n;
    }
    final langs = <String>{
      for (final e in comics)
        if (e.progress.lastLang != null && e.progress.readKeys.isNotEmpty) e.progress.lastLang!,
    };
    final distinctGenres = <String>{
      for (final e in list) for (final t in e.work.tags) if (!t.startsWith('★')) t.toLowerCase(),
    };
    int typeCount(ContentType t) => comics.where((e) => e.work.type == t).length;

    return ReaderStats(
      weekChapters: week,
      monthChapters: month,
      totalMinutes: math.max(total, chapters * 5),
      bestMonth: perMonth.values.fold<int>(0, (a, b) => math.max(a, b)),
      rated: list.where((e) => e.rating != null).length,
      topWorkChapters: topWork?.progress.readKeys.length ?? 0,
      langsRead: langs.length,
      genresCount: distinctGenres.length,
      mangaCount: typeCount(ContentType.manga),
      manhwaCount: typeCount(ContentType.manhwa),
      manhuaCount: typeCount(ContentType.manhua),
      noted: list.where((e) => e.note.trim().isNotEmpty).length,
      chapters: chapters,
      episodes: episodes,
      completed: list.where((e) => e.status == TrackStatus.completed).length,
      library: list.length,
      favorites: list.where((e) => e.favorite).length,
      animeCount: anime.length,
      types: {for (final e in comics) e.work.type},
      currentStreak: current,
      bestStreak: best,
      bestDay: bestDay,
      year: at.year,
      yearChapters: yc,
      yearEpisodes: ye,
      yearMinutes: ym,
      months: months,
      topGenres: top.take(5).toList(),
      topWork: topWork,
      activeDays: active.length,
    );
  }
}

/// Level from experience: level n needs 50·(n−1)² XP.
class Level {
  const Level(this.number, this.xp, this.floor, this.next);
  final int number;
  final int xp;
  final int floor;
  final int next;

  double get progress => next == floor ? 1 : (xp - floor) / (next - floor);

  static int xpFor(int level) => 50 * (level - 1) * (level - 1);

  static Level of(int xp) {
    final n = math.sqrt(xp / 50).floor() + 1;
    return Level(n, xp, xpFor(n), xpFor(n + 1));
  }

  String get title => switch (number) {
        < 3 => 'Novice',
        < 6 => 'Lecteur',
        < 10 => 'Habitué',
        < 15 => 'Passionné',
        < 22 => 'Dévoreur',
        < 30 => 'Otaku',
        < 40 => 'Sensei',
        < 55 => 'Maître',
        _ => 'Légende',
      };
}

class Achievement {
  const Achievement(this.id, this.title, this.description, this.icon, this.target, this.value);
  final String id;
  final String title;
  final String description;

  /// Icon family (book, tv, star, trophy, fire, heart, globe, bolt, shelf,
  /// calendar); the interface maps it to a constant icon.
  final String icon;
  final int target;
  final int Function(ReaderStats s) value;

  double progress(ReaderStats s) => (value(s) / target).clamp(0, 1).toDouble();
  bool done(ReaderStats s) => value(s) >= target;
}

class Achievements {
  static const _book = 'book', _star = 'star', _fire = 'fire', _tv = 'tv',
      _trophy = 'trophy', _heart = 'heart', _globe = 'globe', _bolt = 'bolt',
      _shelf = 'shelf', _calendar = 'calendar', _crown = 'crown', _moon = 'moon',
      _clock = 'clock', _sparkle = 'sparkle', _language = 'language', _pen = 'pen';

  static final all = <Achievement>[
    Achievement('first_chapter', 'Première page', 'Lire un premier chapitre', _book, 1, (s) => s.chapters),
    Achievement('ch_100', 'Centurion', 'Lire 100 chapitres', _book, 100, (s) => s.chapters),
    Achievement('ch_500', 'Rat de bibliothèque', 'Lire 500 chapitres', _book, 500, (s) => s.chapters),
    Achievement('ch_1000', 'Millénaire', 'Lire 1 000 chapitres', _star, 1000, (s) => s.chapters),
    Achievement('ch_5000', 'Bibliothèque vivante', 'Lire 5 000 chapitres', _trophy, 5000, (s) => s.chapters),
    Achievement('ep_1', 'Générique', 'Regarder un premier épisode', _tv, 1, (s) => s.episodes),
    Achievement('ep_100', 'Marathonien', 'Regarder 100 épisodes', _tv, 100, (s) => s.episodes),
    Achievement('ep_500', 'Simulcast addict', 'Regarder 500 épisodes', _trophy, 500, (s) => s.episodes),
    Achievement('complete_1', 'Mot de la fin', 'Terminer une série', _star, 1, (s) => s.completed),
    Achievement('complete_10', 'Collectionneur de fins', 'Terminer 10 séries', _trophy, 10, (s) => s.completed),
    Achievement('library_10', 'Étagère', '10 œuvres dans la bibliothèque', _shelf, 10, (s) => s.library),
    Achievement('library_50', 'Médiathèque', '50 œuvres dans la bibliothèque', _shelf, 50, (s) => s.library),
    Achievement('fav_10', 'Coups de cœur', '10 favoris', _heart, 10, (s) => s.favorites),
    Achievement('streak_7', 'Une semaine sans pause', '7 jours d\'activité d\'affilée', _fire, 7, (s) => s.bestStreak),
    Achievement('streak_30', 'Rituel', '30 jours d\'activité d\'affilée', _fire, 30, (s) => s.bestStreak),
    Achievement('binge_50', 'Nuit blanche', '50 chapitres ou épisodes en une journée', _bolt, 50, (s) => s.bestDay),
    Achievement('explorer', 'Explorateur', 'Suivre un manga, un manhwa et un manhua', _globe, 3,
        (s) => {ContentType.manga, ContentType.manhwa, ContentType.manhua}.where(s.types.contains).length),
    Achievement('crossover', 'Crossover', 'Suivre des lectures et des animés', _globe, 2,
        (s) => (s.library - s.animeCount > 0 ? 1 : 0) + (s.animeCount > 0 ? 1 : 0)),
    Achievement('year_365', 'Un chapitre par jour', '365 chapitres dans l\'année', _calendar, 365, (s) => s.yearChapters),
    Achievement('days_100', 'Fidèle', '100 jours d\'activité', _calendar, 100, (s) => s.activeDays),
    // 2.3.25 : more achievements.
    Achievement('ch_10', 'Mise en bouche', 'Lire 10 chapitres', _book, 10, (s) => s.chapters),
    Achievement('ch_50', 'Premier arc', 'Lire 50 chapitres', _book, 50, (s) => s.chapters),
    Achievement('ch_250', 'Tome après tome', 'Lire 250 chapitres', _book, 250, (s) => s.chapters),
    Achievement('ch_2500', 'Encyclopédie', 'Lire 2 500 chapitres', _star, 2500, (s) => s.chapters),
    Achievement('ch_10000', 'Au-delà du canon', 'Lire 10 000 chapitres', _crown, 10000, (s) => s.chapters),
    Achievement('complete_5', 'Générique de fin', 'Terminer 5 séries', _star, 5, (s) => s.completed),
    Achievement('complete_25', 'Finisseur', 'Terminer 25 séries', _crown, 25, (s) => s.completed),
    Achievement('library_100', 'Grande bibliothèque', '100 œuvres dans la bibliothèque', _shelf, 100, (s) => s.library),
    Achievement('library_250', 'Archiviste', '250 œuvres dans la bibliothèque', _crown, 250, (s) => s.library),
    Achievement('fav_1', 'Coup de foudre', 'Un premier favori', _heart, 1, (s) => s.favorites),
    Achievement('fav_50', 'Cœur d\'artichaut', '50 favoris', _heart, 50, (s) => s.favorites),
    Achievement('streak_3', 'L\'habitude', '3 jours d\'activité d\'affilée', _fire, 3, (s) => s.bestStreak),
    Achievement('streak_14', 'Deux semaines de feu', '14 jours d\'activité d\'affilée', _fire, 14, (s) => s.bestStreak),
    Achievement('streak_100', 'Inarrêtable', '100 jours d\'activité d\'affilée', _crown, 100, (s) => s.bestStreak),
    Achievement('binge_10', 'Une petite dernière', '10 chapitres ou épisodes en une journée', _bolt, 10, (s) => s.bestDay),
    Achievement('binge_100', 'Insomniaque', '100 chapitres ou épisodes en une journée', _moon, 100, (s) => s.bestDay),
    Achievement('week_70', 'Semaine marathon', '70 chapitres ou épisodes en 7 jours', _bolt, 70, (s) => s.weekChapters),
    Achievement('month_300', 'Mois intense', '300 chapitres ou épisodes dans un même mois', _calendar, 300, (s) => s.bestMonth),
    Achievement('days_30', 'Un mois de lecture', '30 jours d\'activité', _calendar, 30, (s) => s.activeDays),
    Achievement('days_365', 'Une année entière', '365 jours d\'activité', _crown, 365, (s) => s.activeDays),
    Achievement('year_1000', 'Année record', '1 000 chapitres dans l\'année', _trophy, 1000, (s) => s.yearChapters),
    Achievement('hours_100', 'Cent heures', 'Environ 100 h de lecture et d\'animés', _clock, 6000, (s) => s.totalMinutes),
    Achievement('one_200', 'Fidèle à une œuvre', '200 chapitres d\'une même œuvre', _sparkle, 200, (s) => s.topWorkChapters),
    Achievement('one_1000', 'Lecteur au long cours', '1 000 chapitres d\'une même œuvre', _crown, 1000, (s) => s.topWorkChapters),
    Achievement('bilingual', 'Bilingue', 'Lire en anglais et en français', _language, 2, (s) => s.langsRead),
    Achievement('genres_10', 'Éclectique', '10 genres différents dans la bibliothèque', _globe, 10, (s) => s.genresCount),
    Achievement('genres_20', 'Touche-à-tout', '20 genres différents dans la bibliothèque', _globe, 20, (s) => s.genresCount),
    Achievement('manga_25', 'Esprit shōnen', 'Suivre 25 mangas', _book, 25, (s) => s.mangaCount),
    Achievement('manhwa_25', 'Accro aux webtoons', 'Suivre 25 manhwas', _book, 25, (s) => s.manhwaCount),
    Achievement('manhua_10', 'Cultivateur', 'Suivre 10 manhuas', _book, 10, (s) => s.manhuaCount),
    Achievement('rated_10', 'Critique', 'Noter 10 œuvres', _pen, 10, (s) => s.rated),
    Achievement('noted_5', 'Carnet de lecture', 'Écrire une note sur 5 œuvres', _pen, 5, (s) => s.noted),
    Achievement('anime_10', 'Saison complète', 'Suivre 10 animés', _tv, 10, (s) => s.animeCount),
    Achievement('level_10', 'Vétéran', 'Atteindre le niveau 10', _sparkle, 10, (s) => Level.of(s.xp).number),
    Achievement('level_25', 'Légende vivante', 'Atteindre le niveau 25', _crown, 25, (s) => Level.of(s.xp).number),
  ];

  /// Newly unlocked achievements (recorded in [log]).
  static List<Achievement> unlock(ReaderStats stats, ActivityLog log, {DateTime? now}) {
    final out = <Achievement>[];
    for (final a in all) {
      if (log.unlocked.containsKey(a.id) || !a.done(stats)) continue;
      log.unlocked[a.id] = (now ?? DateTime.now()).toIso8601String();
      out.add(a);
    }
    return out;
  }
}
