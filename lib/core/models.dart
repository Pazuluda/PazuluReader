import 'chapter_key.dart';

// ---------------------------------------------------------------------------
// Énumérations
// ---------------------------------------------------------------------------

enum ContentType { manga, manhwa, manhua, webtoon, novel, anime, other }

extension ContentTypeLabel on ContentType {
  String get label => switch (this) {
        ContentType.manga => 'Manga',
        ContentType.manhwa => 'Manhwa',
        ContentType.manhua => 'Manhua',
        ContentType.webtoon => 'Webtoon',
        ContentType.novel => 'Roman',
        ContentType.anime => 'Anime',
        ContentType.other => 'Autre',
      };
}

ContentType contentTypeFromName(String? name) => ContentType.values
    .firstWhere((t) => t.name == name, orElse: () => ContentType.other);

enum TrackStatus { discover, planned, reading, paused, completed, dropped }

extension TrackStatusLabel on TrackStatus {
  String get label => switch (this) {
        TrackStatus.discover => 'À découvrir',
        TrackStatus.planned => 'À lire',
        TrackStatus.reading => 'En cours',
        TrackStatus.paused => 'En pause',
        TrackStatus.completed => 'Terminé',
        TrackStatus.dropped => 'Abandonné',
      };
}

TrackStatus trackStatusFromName(String? name) => TrackStatus.values
    .firstWhere((t) => t.name == name, orElse: () => TrackStatus.planned);

enum ReaderMode { vertical, ltr, rtl }

extension ReaderModeLabel on ReaderMode {
  String get label => switch (this) {
        ReaderMode.vertical => 'Vertical (webtoon)',
        ReaderMode.ltr => 'Pages, gauche → droite',
        ReaderMode.rtl => 'Pages, droite → gauche',
      };

  String get shortLabel => switch (this) {
        ReaderMode.vertical => 'Vertical',
        ReaderMode.ltr => 'G → D',
        ReaderMode.rtl => 'D → G',
      };
}

ReaderMode readerModeFromName(String? name) => ReaderMode.values
    .firstWhere((m) => m.name == name, orElse: () => ReaderMode.vertical);

/// Ajustement d'une page en lecture paginée.
enum PageFit { contain, width, height }

extension PageFitLabel on PageFit {
  String get label => switch (this) {
        PageFit.contain => 'Page entière',
        PageFit.width => 'Largeur',
        PageFit.height => 'Hauteur',
      };
}

// ---------------------------------------------------------------------------
// Aides JSON
// ---------------------------------------------------------------------------

List<String> _strList(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

// ---------------------------------------------------------------------------
// Œuvre et sources
// ---------------------------------------------------------------------------

/// Lien entre une œuvre Pazulu et sa fiche sur une source.
class SourceLink {
  const SourceLink({required this.sourceId, required this.workId});

  final String sourceId;
  final String workId;

  Map<String, dynamic> toJson() => {'sourceId': sourceId, 'workId': workId};

  factory SourceLink.fromJson(Map<String, dynamic> json) => SourceLink(
        sourceId: json['sourceId'] as String,
        workId: json['workId'] as String,
      );
}

/// Fiche d'une œuvre (métadonnées).
class WorkInfo {
  const WorkInfo({
    required this.id,
    required this.title,
    this.altTitles = const [],
    this.description = '',
    this.coverUrl,
    this.type = ContentType.other,
    this.publicationStatus,
    this.tags = const [],
    this.year,
    this.authors = const [],
    this.languages = const [],
    this.longStrip = false,
    this.links = const [],
    this.lastChapter,
  });

  final String id;
  final String title;
  final List<String> altTitles;
  final String description;
  final String? coverUrl;
  final ContentType type;
  final String? publicationStatus;
  final List<String> tags;
  final int? year;
  final List<String> authors;

  /// Langues de traduction disponibles (codes ISO, ex. "en", "fr").
  final List<String> languages;

  /// Format « bande verticale » (webtoon) : lecture verticale par défaut.
  final bool longStrip;
  final List<SourceLink> links;
  final String? lastChapter;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'altTitles': altTitles,
        'description': description,
        'coverUrl': coverUrl,
        'type': type.name,
        'publicationStatus': publicationStatus,
        'tags': tags,
        'year': year,
        'authors': authors,
        'languages': languages,
        'longStrip': longStrip,
        'links': links.map((l) => l.toJson()).toList(),
        'lastChapter': lastChapter,
      };

  factory WorkInfo.fromJson(Map<String, dynamic> json) => WorkInfo(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Sans titre',
        altTitles: _strList(json['altTitles']),
        description: (json['description'] as String?) ?? '',
        coverUrl: json['coverUrl'] as String?,
        type: contentTypeFromName(json['type'] as String?),
        publicationStatus: json['publicationStatus'] as String?,
        tags: _strList(json['tags']),
        year: json['year'] as int?,
        authors: _strList(json['authors']),
        languages: _strList(json['languages']),
        longStrip: (json['longStrip'] as bool?) ?? false,
        links: (json['links'] as List? ?? const [])
            .map((e) => SourceLink.fromJson(_map(e)))
            .toList(),
        lastChapter: json['lastChapter'] as String?,
      );
}

/// Un chapitre tel que proposé par UNE source, dans UNE langue, par UN groupe.
/// Plusieurs [SourceChapter] partagent la même [ChapterKey] : ce sont les
/// « Lecteur 1 », « Lecteur 2 »… d'un même chapitre.
class SourceChapter {
  const SourceChapter({
    required this.sourceId,
    required this.chapterId,
    required this.key,
    required this.lang,
    required this.group,
    this.title,
    this.pages = 0,
    this.externalUrl,
    this.publishedAt,
    this.volume,
  });

  final String sourceId;
  final String chapterId;
  final ChapterKey key;
  final String lang;
  final String group;
  final String? title;
  final int pages;
  final String? externalUrl;
  final DateTime? publishedAt;
  final String? volume;

  /// Chapitre hébergé sur le site officiel de l'éditeur (lien externe).
  bool get isExternal => externalUrl != null && externalUrl!.trim().isNotEmpty;

  String get langLabel => lang.toUpperCase();

  Map<String, dynamic> toJson() => {
        's': sourceId,
        'c': chapterId,
        'k': key.id,
        'l': lang,
        'g': group,
        if (title != null) 't': title,
        if (pages > 0) 'p': pages,
        if (externalUrl != null) 'x': externalUrl,
        if (publishedAt != null) 'd': publishedAt!.toIso8601String(),
        if (volume != null) 'v': volume,
      };

  static SourceChapter? fromJson(Object? raw) {
    if (raw is! Map || raw['s'] is! String || raw['c'] is! String ||
        raw['k'] is! String || raw['l'] is! String) {
      return null;
    }
    return SourceChapter(
      sourceId: raw['s'] as String,
      chapterId: raw['c'] as String,
      key: ChapterKey.parse(raw['k'] as String),
      lang: raw['l'] as String,
      group: raw['g'] is String ? raw['g'] as String : '',
      title: raw['t'] is String ? raw['t'] as String : null,
      pages: raw['p'] is int ? raw['p'] as int : 0,
      externalUrl: raw['x'] is String ? raw['x'] as String : null,
      publishedAt: raw['d'] is String ? DateTime.tryParse(raw['d'] as String) : null,
      volume: raw['v'] is String ? raw['v'] as String : null,
    );
  }
}

class PageRef {
  const PageRef(this.url, {this.fallbackUrl});

  final String url;
  final String? fallbackUrl;
}

// ---------------------------------------------------------------------------
// Bibliothèque personnelle
// ---------------------------------------------------------------------------

class ReadingProgress {
  ReadingProgress({
    this.lastKey,
    this.lastPage = 0,
    Set<String>? readKeys,
    this.updatedAt,
    this.lastLang,
    this.lastGroup,
  }) : readKeys = readKeys ?? <String>{};

  String? lastKey;
  int lastPage;
  Set<String> readKeys;
  DateTime? updatedAt;
  String? lastLang;
  String? lastGroup;

  Map<String, dynamic> toJson() => {
        'lastKey': lastKey,
        'lastPage': lastPage,
        'readKeys': readKeys.toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'lastLang': lastLang,
        'lastGroup': lastGroup,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        lastKey: json['lastKey'] as String?,
        lastPage: (json['lastPage'] as int?) ?? 0,
        readKeys: _strList(json['readKeys']).toSet(),
        updatedAt: _date(json['updatedAt']),
        lastLang: json['lastLang'] as String?,
        lastGroup: json['lastGroup'] as String?,
      );
}

/// Lien enregistré manuellement vers une œuvre sur un des sites du catalogue.
/// La présence d'un lien ne donne pas à Pazulu l'autorisation d'en extraire les pages.
class SavedSiteLink {
  const SavedSiteLink({required this.siteId, required this.url, required this.lang});

  final String siteId;
  final String url;
  final String lang;

  Map<String, dynamic> toJson() => {'siteId': siteId, 'url': url, 'lang': lang};

  factory SavedSiteLink.fromJson(Map<String, dynamic> json) => SavedSiteLink(
        siteId: json['siteId'] as String,
        url: json['url'] as String,
        lang: (json['lang'] as String?) ?? 'en',
      );
}

class LibraryEntry {
  LibraryEntry({
    required this.work,
    this.status = TrackStatus.planned,
    this.favorite = false,
    this.watch = true,
    this.rating,
    List<String>? tags,
    this.note = '',
    ReadingProgress? progress,
    DateTime? addedAt,
    DateTime? updatedAt,
    this.preferredLang,
    this.preferredGroup,
    this.preferredSourceId,
    this.readerModeOverride,
    Map<String, List<String>>? releaseDates,
    List<int>? readingDays,
    this.readingGoal = 1,
    this.webLookupAt,
    this.episodesWatched = 0,
    Map<String, double>? latestKnown,
    Map<String, List<String>>? observedChapters,
    List<SavedSiteLink>? savedSiteLinks,
  })  : tags = tags ?? <String>[],
        progress = progress ?? ReadingProgress(),
        addedAt = addedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        latestKnown = latestKnown ?? <String, double>{},
        releaseDates = releaseDates ?? <String, List<String>>{},
        readingDays = readingDays ?? <int>[],
        observedChapters = observedChapters ?? <String, List<String>>{},
        savedSiteLinks = savedSiteLinks ?? <SavedSiteLink>[];

  WorkInfo work;
  TrackStatus status;
  bool favorite;

  /// Surveiller les nouvelles sorties de cette œuvre.
  bool watch;
  int? rating;
  List<String> tags;
  String note;
  ReadingProgress progress;
  DateTime addedAt;
  DateTime updatedAt;

  /// Lecteur choisi par défaut (« Définir par défaut »).
  String? preferredLang;
  String? preferredGroup;
  String? preferredSourceId;

  /// Sens de lecture choisi pour CETTE œuvre (la détection automatique reste
  /// modifiable). Null = automatique.
  ReaderMode? readerModeOverride;

  /// Planning : dates de sortie observées par langue (ISO, plus récentes en
  /// premier, 16 maximum). Sert à estimer la prochaine sortie.
  Map<String, List<String>> releaseDates;

  /// Planning personnel : jours de lecture (1 = lundi … 7 = dimanche).
  List<int> readingDays;

  /// Objectif de chapitres par séance de lecture.
  int readingGoal;

  /// Dernière recherche de lecteurs sur tous les sites (mémorisée : elle
  /// n'est relancée qu'en arrière-plan, au plus une fois par semaine).
  DateTime? webLookupAt;

  /// Animés : épisodes vus.
  int episodesWatched;

  /// Dernier numéro de chapitre connu par langue (détection des nouveautés).
  Map<String, double> latestKnown;

  /// Historique des numéros vus par source ET langue. Évite de manquer une
  /// traduction tardive d'un chapitre plus ancien que le maximum connu.
  Map<String, List<String>> observedChapters;

  /// Adresses d'œuvres enregistrées par l'utilisateur sur ses sites favoris.
  List<SavedSiteLink> savedSiteLinks;

  Map<String, dynamic> toJson() => {
        'work': work.toJson(),
        'status': status.name,
        'favorite': favorite,
        'watch': watch,
        'rating': rating,
        'tags': tags,
        'note': note,
        'progress': progress.toJson(),
        'addedAt': addedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'preferredLang': preferredLang,
        'preferredGroup': preferredGroup,
        'preferredSourceId': preferredSourceId,
        'readerModeOverride': readerModeOverride?.name,
        'releaseDates': releaseDates,
        'readingDays': readingDays,
        'readingGoal': readingGoal,
        'webLookupAt': webLookupAt?.toIso8601String(),
        'episodesWatched': episodesWatched,
        'latestKnown': latestKnown,
        'observedChapters': observedChapters,
        'savedSiteLinks': savedSiteLinks.map((l) => l.toJson()).toList(),
      };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        work: WorkInfo.fromJson(_map(json['work'])),
        status: trackStatusFromName(json['status'] as String?),
        favorite: (json['favorite'] as bool?) ?? false,
        watch: (json['watch'] as bool?) ?? true,
        rating: json['rating'] as int?,
        tags: _strList(json['tags']),
        note: (json['note'] as String?) ?? '',
        progress: ReadingProgress.fromJson(_map(json['progress'])),
        addedAt: _date(json['addedAt']),
        updatedAt: _date(json['updatedAt']),
        preferredLang: json['preferredLang'] as String?,
        preferredGroup: json['preferredGroup'] as String?,
        preferredSourceId: json['preferredSourceId'] as String?,
        releaseDates: _map(json['releaseDates']).map((k, v) => MapEntry(k, _strList(v))),
        readingDays: [
          for (final d in (json['readingDays'] as List? ?? const []))
            if (d is int && d >= 1 && d <= 7) d,
        ],
        webLookupAt: json['webLookupAt'] is String
            ? DateTime.tryParse(json['webLookupAt'] as String) : null,
        episodesWatched: json['episodesWatched'] is int ? json['episodesWatched'] as int : 0,
        readingGoal: json['readingGoal'] is int ? (json['readingGoal'] as int).clamp(1, 50).toInt() : 1,
        readerModeOverride: json['readerModeOverride'] is String
            ? readerModeFromName(json['readerModeOverride'] as String)
            : null,
        latestKnown: _map(json['latestKnown']).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
        observedChapters: _map(json['observedChapters']).map((k, v) =>
            MapEntry(k, _strList(v))),
        savedSiteLinks: [
          for (final l in (json['savedSiteLinks'] as List? ?? const []))
            if (l is Map) SavedSiteLink.fromJson(l.cast<String, dynamic>()),
        ],
      );
}

/// Une nouvelle sortie détectée.
class UpdateItem {
  UpdateItem({
    required this.workId,
    required this.title,
    required this.keyId,
    required this.lang,
    required this.group,
    required this.foundAt,
    this.coverUrl,
    this.siteId,
    this.chapterUrl,
    this.seen = false,
    this.publishedAt,
  });

  /// Real publication date given by the source (null if unknown).
  final DateTime? publishedAt;

  /// When the chapter was really released, as far as Pazulu knows.
  DateTime get releasedAt => publishedAt ?? foundAt;

  final String workId;
  final String title;
  final String? coverUrl;
  /// Source reference for a publicly listed chapter (if applicable).
  final String? siteId;
  /// Official chapter link. Does not imply that images are extractable.
  final String? chapterUrl;
  final String keyId;
  final String lang;
  final String group;
  final DateTime foundAt;
  bool seen;

  /// Une notification = (œuvre, chapitre, langue) : pas de doublon.
  String get id => '$workId|$keyId|$lang';

  ChapterKey get key => ChapterKey.parse(keyId);

  Map<String, dynamic> toJson() => {
        'workId': workId,
        'title': title,
        'coverUrl': coverUrl,
        'siteId': siteId,
        'chapterUrl': chapterUrl,
        'keyId': keyId,
        'lang': lang,
        'group': group,
        'foundAt': foundAt.toIso8601String(),
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
        'seen': seen,
      };

  factory UpdateItem.fromJson(Map<String, dynamic> json) => UpdateItem(
        workId: json['workId'] as String,
        title: (json['title'] as String?) ?? '',
        coverUrl: json['coverUrl'] as String?,
        siteId: json['siteId'] as String?,
        chapterUrl: json['chapterUrl'] as String?,
        keyId: json['keyId'] as String,
        lang: (json['lang'] as String?) ?? 'en',
        group: (json['group'] as String?) ?? '',
        foundAt: _date(json['foundAt']) ?? DateTime.now(),
        seen: (json['seen'] as bool?) ?? false,
        publishedAt: _date(json['publishedAt']),
      );
}

class Settings {
  Settings({
    List<String>? comicLangs,
    this.readerMode = ReaderMode.vertical,
    this.gridColumns = 0,
    this.reduceMotion = false,
    this.includeSuggestive = true,
    this.checkOnStartup = true,
    this.autoCheckMinutes = 60,
    this.cacheOnRead = true,
    this.verticalMaxWidth = 900,
    this.themeId = 'jaune',
    this.darkMode = false,
    this.updateRepo = '',
    this.autoUpdateCheck = true,
    this.autoFailover = true,
    this.browserReader = false,
    List<String>? blockedSources,
    this.crossLanguageFallback = true,
    this.doublePage = false,
    this.pageFit = PageFit.contain,
    this.langChosen = false,
    List<String>? recentSearches,
  })  : comicLangs = comicLangs ?? <String>['en', 'fr'],
        blockedSources = blockedSources ?? <String>[],
        recentSearches = recentSearches ?? <String>[];

  /// The first-launch question « English or French first? » was answered.
  bool langChosen;

  /// Last searches of Discover (newest first, 12 max).
  List<String> recentSearches;

  /// Langues de lecture, par ordre de préférence.
  List<String> comicLangs;
  ReaderMode readerMode;

  /// 0 = automatique selon la largeur.
  int gridColumns;
  bool reduceMotion;
  bool includeSuggestive;
  bool checkOnStartup;

  /// A chapter's image pages are fetched and stored locally only when reading
  /// begins, never during discovery, search, or metadata inspection.
  bool cacheOnRead;

  /// Vérification tant que l'application est ouverte, en minutes (0 = arrêt).
  int autoCheckMinutes;

  /// Largeur max des pages en lecture verticale (grands écrans).
  double verticalMaxWidth;

  /// Palette de couleurs choisie (voir design/theme.dart).
  String themeId;

  /// Mode sombre (encre) ou clair (papier) — Kiosque 2.4.
  bool darkMode;

  /// GitHub « owner/repo » whose Releases carry the Windows ZIP (empty =
  /// the built-in one, [defaultUpdateRepo]).
  String updateRepo;

  /// Look for a new version at start and every 6 hours.
  bool autoUpdateCheck;

  /// Moteur 2.0 : basculer automatiquement vers un autre lecteur du MÊME
  /// chapitre quand la source choisie échoue.
  bool autoFailover;

  /// Hidden WebView2 for JavaScript-only chapters. Off by default on
  /// Windows: the native window can cover the app (black screen); the
  /// other readers are used instead.
  bool browserReader;

  /// Sources the user excluded (wrong language, bad quality…): never
  /// searched, listed, read or used by the planning.
  List<String> blockedSources;

  /// Autoriser ce repli vers une autre langue de la liste de préférences.
  bool crossLanguageFallback;

  /// Double page en lecture paginée (manga/BD).
  bool doublePage;

  /// Ajustement des pages en lecture paginée.
  PageFit pageFit;

  Map<String, dynamic> toJson() => {
        'comicLangs': comicLangs,
        'readerMode': readerMode.name,
        'gridColumns': gridColumns,
        'reduceMotion': reduceMotion,
        'includeSuggestive': includeSuggestive,
        'checkOnStartup': checkOnStartup,
        'cacheOnRead': cacheOnRead,
        'autoCheckMinutes': autoCheckMinutes,
        'verticalMaxWidth': verticalMaxWidth,
        'themeId': themeId,
        'darkMode': darkMode,
        'updateRepo': updateRepo,
        'autoUpdateCheck': autoUpdateCheck,
        'autoFailover': autoFailover,
        'browserReader': browserReader,
        'blockedSources': blockedSources,
        'crossLanguageFallback': crossLanguageFallback,
        'doublePage': doublePage,
        'pageFit': pageFit.name,
        'langChosen': langChosen,
        'recentSearches': recentSearches,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    final langs = _strList(json['comicLangs']);
    return Settings(
      comicLangs: langs.isEmpty ? null : langs,
      readerMode: readerModeFromName(json['readerMode'] as String?),
      gridColumns: (json['gridColumns'] as int?) ?? 0,
      reduceMotion: (json['reduceMotion'] as bool?) ?? false,
      includeSuggestive: (json['includeSuggestive'] as bool?) ?? true,
      checkOnStartup: (json['checkOnStartup'] as bool?) ?? true,
      cacheOnRead: (json['cacheOnRead'] as bool?) ?? true,
      autoCheckMinutes: [0, 15, 30, 60, 120].contains(json['autoCheckMinutes'])
          ? json['autoCheckMinutes'] as int : 60,
      verticalMaxWidth:
          (json['verticalMaxWidth'] as num?)?.toDouble() ?? 900,
      themeId: (json['themeId'] as String?) ?? 'jaune',
      darkMode: (json['darkMode'] as bool?) ?? false,
      updateRepo: (json['updateRepo'] as String?) ?? '',
      autoUpdateCheck: (json['autoUpdateCheck'] as bool?) ?? true,
      autoFailover: (json['autoFailover'] as bool?) ?? true,
      browserReader: (json['browserReader'] as bool?) ?? false,
      blockedSources: [
        for (final v in (json['blockedSources'] is List ? json['blockedSources'] as List : const []))
          if (v is String) v,
      ],
      crossLanguageFallback: (json['crossLanguageFallback'] as bool?) ?? true,
      doublePage: (json['doublePage'] as bool?) ?? false,
      pageFit: PageFit.values.firstWhere((f) => f.name == json['pageFit'],
          orElse: () => PageFit.contain),
      langChosen: (json['langChosen'] as bool?) ?? false,
      recentSearches: _strList(json['recentSearches']).take(12).toList(),
    );
  }
}
