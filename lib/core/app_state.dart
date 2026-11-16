import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'chapter_consensus.dart';
import 'chapter_key.dart';
import 'catalogue_audit.dart';
import 'chapter_identity.dart';
import 'chapter_listing.dart';
import 'chapters.dart';
import 'downloads.dart';
import 'discovery.dart';
import 'library_store.dart';
import 'log.dart';
import 'anime/anilist.dart';
import 'anime/fr_planning.dart';
import 'anime/crunchyroll.dart';
import 'models.dart';
import 'planning.dart';
import 'achievements.dart';
import 'bookmarks_import.dart';
import 'coverage.dart';
import 'device_profile.dart';
import 'french_text.dart';
import 'host_gate.dart';
import 'recap.dart';
import 'zip_writer.dart';
import 'library_insights.dart';
import 'moments.dart';
import 'language_consensus.dart';
import 'app_update.dart';
import 'schedule/mangaupdates.dart';
import 'schedule/schedule_service.dart';
import 'schedule/weekly_schedule.dart';
import 'release_detector.dart';
import 'release_scan.dart';
import 'site_index.dart';
import 'work_status.dart';
import 'source_catalog.dart';
import 'community_sources.dart';
import 'suggested_sources.dart';
import 'source_extensions.dart';
import 'source_health.dart';
import 'user_sources.dart';
import 'page_inspection.dart';
import 'sources/session_capture.dart';
import 'source.dart';
import 'source_routing.dart';
import 'sources/mangadex.dart';
import 'sources/peppercarrot.dart';
import 'sources/public_catalog.dart';
import 'sources/sushiscan.dart';
import '../engine/availability.dart';
import '../engine/diagnostics/connector_health.dart';
import '../engine/diagnostics/source_status.dart';
import '../engine/http/engine_http.dart' show CancelToken;
import '../engine/identity/canonical_chapter.dart';
import '../engine/identity/listing_guard.dart';
import '../engine/pazulu_engine.dart';
import '../engine/routing/smart_router.dart';
import '../extensions/pack.dart';
import '../extensions/registry.dart';

const String appVersion = '1.9.4';

/// GitHub repository of the official releases (« owner/repo »). Empty until
/// the repository exists: Réglages › Mises à jour can set one meanwhile.
const String defaultUpdateRepo = 'Pazuluda/PazuluReader';

/// Live progress of a multisource search / browse / reader lookup.
class SearchProgress {
  const SearchProgress({this.total = 0, this.done = 0, this.failed = 0, this.found = 0});
  final int total;
  final int done;
  final int failed;
  final int found;
  bool get running => done < total;
  double get ratio => total == 0 ? 1 : done / total;
}

class ReaderLookupReport {
  const ReaderLookupReport({required this.checked, required this.found,
    required this.unavailable});
  final int checked;
  final int found;
  final int unavailable;
}

/// État global de l'application : bibliothèque, réglages, sources, nouveautés.
class AppState extends ChangeNotifier {
  // ------------------------------------------------------------ reading
  // While a chapter is read, background work (catalogues, sources, new
  // chapters) goes on, but the screens behind the reader are rebuilt at
  // most every 3 s instead of at every step, and background loops pause
  // a little between two sites: no stutter in the reader.
  int _readersOpen = 0;
  Timer? _quietNotify;

  bool get reading => _readersOpen > 0;

  void readerOpened() => _readersOpen++;

  void readerClosed() {
    if (_readersOpen > 0) _readersOpen--;
    if (_readersOpen == 0) {
      _quietNotify?.cancel();
      _quietNotify = null;
      _notifyNow();
    }
  }

  /// Increases at every real refresh of the screens: a page can keep what
  /// it computed (unread counts…) while it has not changed.
  int revision = 0;

  void _notifyNow() {
    revision++;
    super.notifyListeners();
  }

  DateTime _lastNotify = DateTime(2000);
  Timer? _trailingNotify;

  /// Background work (catalogues, chapters, statuses) may ask for many
  /// refreshes per second: the screens are rebuilt at once, then at most
  /// once per [DeviceProfile.notifyGap] (the last change is never lost).
  @override
  void notifyListeners() {
    if (_readersOpen == 0) {
      if (_trailingNotify != null) return;
      final since = DateTime.now().difference(_lastNotify);
      final gap = DeviceProfile.notifyGap;
      if (since >= gap) {
        _lastNotify = DateTime.now();
        _notifyNow();
        return;
      }
      _trailingNotify = Timer(gap - since, () {
        _trailingNotify = null;
        _lastNotify = DateTime.now();
        _notifyNow();
      });
      return;
    }
    _quietNotify ??= Timer(const Duration(seconds: 3), () {
      _quietNotify = null;
      _notifyNow();
    });
  }

  /// Short pause between two background requests while reading.
  /// Also waits while the window is minimised / in the background (a game
  /// in front): the background work resumes when Pazulu comes back.
  Future<void> _breathe() async {
    while (!_active && !_disposed) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // Light mode (modest PC): background work steps aside while the user
    // scrolls, clicks or types, and resumes 4 s after the last action.
    while (DeviceProfile.light && !_disposed && !_splashWork &&
        DateTime.now().difference(_userActiveAt) < const Duration(seconds: 4)) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (reading) await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  DateTime _userActiveAt = DateTime(2000);

  /// Called on every click, scroll or key press (main.dart).
  void touch() => _userActiveAt = DateTime.now();

  /// The start-up update runs on the splash screen (light mode): nobody is
  /// using the app yet, no need to step aside.
  bool _splashWork = false;

  bool _disposed = false;

  /// Current background step (catalogues, chapters…), shown discreetly in
  /// the header; null = nothing running.
  final ValueNotifier<String?> backgroundStep = ValueNotifier(null);

  Future<void>? _indexLoading;

  AppState() : _mangadex = MangaDexSource() {
    sources = SourceRegistry([_mangadex, _peppercarrot, _sushiscan, _captures]);
  }

  final MangaDexSource _mangadex;
  final PepperCarrotSource _peppercarrot = PepperCarrotSource();
  final SessionCaptureSource _captures = SessionCaptureSource();
  final SushiScanSource _sushiscan = SushiScanSource();

  /// Pazulu Source Engine 2.0 (HTTP sûr, validation, routeur, extensions).
  final PazuluEngine engine = PazuluEngine();
  final Set<String> _declarativeIds = {};
  Directory? _supportDir;
  List<String> extensionWarnings = const [];
  /// Only actual first-party Dart adapters are native; site addresses are not.
  int get nativeReaderCount => sources.all.where((source) =>
      source is! PublicCatalogSource && source.id != _captures.id).length;
  List<ContentSource> get nativeSources => sources.all.where((source) =>
      source is! PublicCatalogSource && source.id != _captures.id).toList();

  SourceRecipeRegistry _recipes = SourceRecipeRegistry.defaults();
  SourceRecipeStore? _recipeStore;
  UserSourceStore? _userSourceStore;
  SourceHealthStore? _sourceHealthStore;
  final List<UserSource> _userSources = [];
  final List<CatalogSite> _directorySites = [];
  List<CatalogSite> get directorySources => List.unmodifiable(_directorySites);

  final Map<String, SourceHealth> _sourceHealth = {};
  Timer? _healthTimer;
  bool checkingSources = false;
  DateTime? lastHealthCheckAt;
  final SourceHealthProbe _healthProbe = const SourceHealthProbe();

  /// Sources available in the application. Directory entries are browser
  /// addresses, NOT automatically verified native chapter connectors.
  /// Keep personal IDs when a user added the same site in an earlier release.
  List<CatalogSite> get activeSources {
    final personal = _userSources.where((s) => s.enabled)
        .map((s) => s.toCatalogSite()).toList();
    final seen = <String>{
      for (final site in catalogSites) _normalizedHost(site.home),
      for (final site in personal) _normalizedHost(site.home),
    };
    return [
      ...catalogSites,
      ...personal,
      for (final site in _directorySites)
        if (seen.add(_normalizedHost(site.home))) site,
    ];
  }

  static String _normalizedHost(String url) => Uri.parse(url).host.toLowerCase()
      .replaceFirst(RegExp(r'^www\.'), '');
  List<UserSource> get personalSources => List.unmodifiable(_userSources);
  CatalogSite? siteById(String id) {
    for (final source in _userSources) {
      if (source.id == id) return source.toCatalogSite();
    }
    for (final site in _directorySites) {
      if (site.id == id) return site;
    }
    return catalogSiteById(id);
  }
  SourceHealth? healthFor(String id) => _sourceHealth[id];

  SourceRecipeRegistry get extensionRecipes => _recipes;
  late final SourceRegistry sources;

  LibraryStore? _store;
  LibraryData _data = LibraryData();
  Timer? _saveTimer;
  Timer? _checkTimer;
  bool _active = true;
  int _consecutiveFailures = 0;

  bool ready = false;
  String? loadWarning;

  bool checking = false;
  String? lastCheckError;
  DateTime? lastCheckAt;

  final Map<String, List<SourceChapter>> _chapterCache = {};
  final Map<String, DateTime> _chapterCachedAt = {};
  final Map<String, List<CatalogueCheck>> _catalogueChecks = {};
  List<CatalogueCheck> catalogueChecksFor(String workId) =>
      List.unmodifiable(_catalogueChecks[workId] ?? const <CatalogueCheck>[]);

  final Map<String, Future<List<ChapterGroup>>> _chapterLoads = {};
  final Map<String, List<SourceLink>> _locatedReaderLinks = {};

  /// Catalogues of every site, kept on disk (see [crawlSiteIndex]).
  SiteTitleIndex siteIndex = SiteTitleIndex(null);

  /// Live progress of the catalogue crawl (splash, Discover).
  SearchProgress? indexProgress;
  final Map<String, DateTime> _nativeDiscoveryAt = {};



  /// Polling is restricted to user-saved work links, never site-wide crawling.
  final ChapterListingFetcher _listingFetcher = const ChapterListingFetcher();
  final Map<String, DateTime> _lastListingChecks = {};
  DateTime? lastListingCheckAt;
  int listingChecks = 0;
  int listingFailures = 0;
  String? lastListingError;
  final List<FeedCheckResult> _feedCheckResults = [];
  List<FeedCheckResult> get feedChecks => List.unmodifiable(_feedCheckResults);
  int get verifiedFeeds => _feedCheckResults.where((e) => e.confirmed).length;
  int get failedFeeds => _feedCheckResults.where((e) =>
      e.state == FeedCheckState.failed ||
      e.state == FeedCheckState.unavailable ||
      e.state == FeedCheckState.rateLimited).length;
  int get confirmedUnread => <String>{
    for (final report in _feedCheckResults)
      if (report.confirmed)
        for (final key in report.unreadKeys) '${report.workId}|$key',
  }.length;


  DownloadStore? _downloads;

  /// Téléchargements en cours : identifiant du chapitre → avancement 0..1.
  final Map<String, double> downloading = {};
  final Map<String, Future<void>> _downloadTasks = {};

  // A failing chapter is deprioritized briefly, never permanently deleted.
  final Map<String, DateTime> _recentChapterFailures = {};

  bool chapterRecentlyFailed(String chapterId) {
    final at = _recentChapterFailures[chapterId];
    if (at == null) return false;
    if (DateTime.now().difference(at) > const Duration(minutes: 30)) {
      _recentChapterFailures.remove(chapterId);
      return false;
    }
    return true;
  }

  void reportChapterFailure(SourceChapter chapter, Object failure) {
    _recentChapterFailures[chapter.chapterId] = DateTime.now();
    AppLog.info('Lecteur provisoirement indisponible: ${chapter.sourceId} '
      'chapitre ${chapter.key.id}: $failure');
  }

  void reportChapterSuccess(SourceChapter chapter) {
    _recentChapterFailures.remove(chapter.chapterId);
  }

  List<SourceChapter> usableReaders(List<SourceChapter> variants, {
    String? preferredSourceId,
    String? preferredLang,
  }) {
    final routed = SourceRouting.rank(variants,
      preferredLanguages: settings.comicLangs,
      isCached: (id) => downloadOf(id) != null,
      hasConnector: (id) => sources.byId(id) != null,
      recentlyFailed: chapterRecentlyFailed);
    // Engine 2.0: inside the same tier and language, prefer the reader the
    // user pinned, then measured reliability / latency.
    final pinned = routed.isEmpty ? null : routed.first;
    int tier(SourceChapter c) => switch (SourceRouting.access(c,
        isCached: (id) => downloadOf(id) != null,
        hasConnector: (id) => sources.byId(id) != null,
        recentlyFailed: chapterRecentlyFailed)) {
      SourceAccess.offline => 0,
      SourceAccess.native => 1,
      SourceAccess.temporarilyUnavailable => 2,
      SourceAccess.unsupported => 3,
      SourceAccess.external => 4,
    };
    int lang(SourceChapter c) {
      final i = settings.comicLangs.indexOf(c.lang);
      return i < 0 ? 99 : i;
    }
    final refined = engine.ranker.refine(routed, tier: tier, langRank: lang,
        preferredSourceId: preferredSourceId);
    // Keep the explicitly preferred reader (rankVariants put it first) on top.
    if (pinned != null && preferredSourceId != null &&
        pinned.sourceId == preferredSourceId && refined.first != pinned) {
      refined
        ..remove(pinned)
        ..insert(0, pinned);
    }
    // « Lire en FR » : a readable reader in the chosen language always
    // comes before any other language, even an offline copy in English.
    if (preferredLang != null) {
      final first = [
        for (final c in refined)
          if (c.lang == preferredLang && isPazuluReadable(c)) c,
      ];
      if (first.isNotEmpty) {
        return [...first, for (final c in refined) if (!first.contains(c)) c];
      }
    }
    return refined;
  }

  /// A temporarily unavailable connector is kept as a manual reader choice.
  /// This does not promise that the source works, and does not use a site
  /// from the catalogue without an installed page connector.
  bool isPazuluRetryable(SourceChapter chapter) =>
      downloadOf(chapter.chapterId) != null ||
      (!chapter.isExternal && sources.byId(chapter.sourceId) != null);

  bool isPazuluReadable(SourceChapter chapter) => SourceRouting.canOpenInPazulu(
    chapter,
    isCached: (id) => downloadOf(id) != null,
    hasConnector: (id) => sources.byId(id) != null,
    recentlyFailed: chapterRecentlyFailed);


  Settings get settings => _data.settings;
  Iterable<LibraryEntry> get entries => _data.entries.values;
  List<UpdateItem> get updates => _data.updates;
  int get unseenUpdates => _data.updates.where((u) => !u.seen).length;
  String? get dataPath => _store?.dir.path;

  // -------------------------------------------------------------------------
  // Démarrage et sauvegarde
  // -------------------------------------------------------------------------

  Future<void> init({void Function(String step)? onStep}) async {
    try {
      onStep?.call('Ouverture du profil…');
      final dir = await getApplicationSupportDirectory();
      _supportDir = dir;
      AppLog.init(dir);
      _recipeStore = SourceRecipeStore(File('${dir.path}${Platform.pathSeparator}source-extensions.json'));
      _recipes = await _recipeStore!.load();
      _userSourceStore = UserSourceStore(File('${dir.path}${Platform.pathSeparator}user-sources.json'));
      _sourceHealthStore = SourceHealthStore(File('${dir.path}${Platform.pathSeparator}source-health.json'));
      // Bundled source addresses load separately from library.json and never
      // overwrite the user's chapter progress or backups.
      onStep?.call('Chargement des sources…');
      try {
        _directorySites.addAll(CommunitySourceDirectory.fromSuggestions(
          await SuggestedSourceCatalog.load(),
        ));
      } catch (error) {
        AppLog.error('Repertoire des 200 sites indisponible', error);
      }
      try {
        _userSources.addAll(await _userSourceStore!.load());
      } catch (e) {
        AppLog.error('Catalogue personnel illisible (original conserve)', e);
      }
      try {
        _sourceHealth.addAll(await _sourceHealthStore!.load());
      } catch (e) {
        AppLog.error('Historique sante des sources illisible', e);
      }
      // Lightweight metadata adapters are registered for saved-work restore.
      // This performs NO HTTP call and never downloads chapter images.
      for (final site in activeSources) {
        if (!site.hasReaderConnector) _publicConnectorFor(site);
      }
      onStep?.call('Préparation du moteur de lecture…');
      await _initEngine(dir);
      await _loadLocatedReaders();
      await _loadMoments();
      await _loadFrenchSummaries();
      await _loadHistory();
      final diagDir = Directory('${dir.path}${Platform.pathSeparator}diagnostics');
      PublicCatalogSource.onDiagnosticPage = (sourceId, kind, url, body) {
        // One file per site and kind (overwritten), 2 MB max.
        unawaited(() async {
          try {
            await diagDir.create(recursive: true);
            final f = File('${diagDir.path}${Platform.pathSeparator}$sourceId-$kind.html');
            final text = body.length > 2000000 ? body.substring(0, 2000000) : body;
            await f.writeAsString('<!-- $url -->\n$text');
          } catch (_) {}
        }());
      };
      siteIndex = SiteTitleIndex(
          File('${dir.path}${Platform.pathSeparator}site-index.json'));
      // Hundreds of thousands of titles: loaded in background, the library
      // opens without waiting (searches use it as soon as it is there).
      _indexLoading = siteIndex.load().then((_) => notifyListeners());
      onStep?.call('Chargement de la bibliothèque…');
      AppLog.info('Démarrage de Pazulu Reader $appVersion');
      final store = LibraryStore(dir);
      _store = store;
      final downloads = DownloadStore(dir);
      await downloads.load();
      _downloads = downloads;
      final result = await store.load();
      _data = result.data;
      DeviceProfile.mode = _data.settings.performanceMode;
      loadWarning = result.warning;
      // Old versions could notify years-old or foreign chapters: clean them.
      var removed = UpdateHygiene.clean(_data.updates, _data.entries);
      final before = _data.updates.length;
      _data.updates.removeWhere((u) {
        final e = _data.entries[u.workId];
        if (e == null || u.siteId != null) return false;
        if (LanguageConsensus.heldBySingleSourceAhead(e, u.lang, u.keyId)) return true;
        final holders = [
          for (final b in e.observedChapters.entries)
            if (b.key.endsWith('|${u.lang}') && b.value.contains(u.keyId)) b.key.split('|').first,
        ];
        return holders.length == 1 &&
            LanguageConsensus.singleSourceAhead(e, holders.single, u.lang, u.keyId);
      });
      removed += before - _data.updates.length;
      if (removed > 0) {
        AppLog.info('Nouveautés : $removed notification(s) incohérente(s) retirée(s)');
        unawaited(store.save(_data).catchError((Object e) {
          AppLog.error('Sauvegarde après nettoyage', e);
        }));
      }
      unawaited(store.autoBackup(_data, appVersion).catchError((Object e) {
        AppLog.error('Sauvegarde automatique', e);
      }));
    } catch (e, st) {
      AppLog.error('Chargement de la bibliothèque', e, st);
      loadWarning = 'Impossible de charger la bibliothèque : $e';
    }
    _applySourceSettings();
    ready = true;
    // 100% embedded Dart sources. No background server or APK extension.
    // No chapter/page HTTP requests are issued during startup.
    _scheduleAutoChecks();
    _scheduleSourceHealthChecks(initial: true);
    notifyListeners();
    // Whole library: works whose chapter list has holes or stops before
    // the announced last chapter get other readers, quietly, one by one.
    Timer(const Duration(seconds: 45), () => unawaited(repairLibraryCoverage()));
    // Works without a cover (imported from bookmarks…): their fiche is
    // completed from AniList (metadata only).
    Timer(const Duration(seconds: 25), () => unawaited(enrichLibraryMetadata()));
    // Other titles of the works (rare names after an import…).
    Timer(const Duration(seconds: 70), () => unawaited(enrichAliases()));
    // Achievements already earned by the existing library.
    Timer(const Duration(seconds: 3), _checkAchievements);
    // The week's planning is prepared quietly: the tab opens instantly.
    Timer(const Duration(seconds: 90), () {
      if (_active) {
        unawaited(schedule.load(WeeklyScheduleBuilder.weekStart(DateTime.now())));
      }
    });
    // Releases are checked by warmUp() on the splash (main.dart).
  }

  void _applySourceSettings() {
    _mangadex.contentRatings =
        settings.includeSuggestive ? const ['safe', 'suggestive'] : const ['safe'];
  }

  /// Le minuteur ne tourne que lorsque l'application est ouverte/active.
  /// Les tâches de fond nécessiteraient une implémentation propre à chaque OS.
  void setActive(bool active) {
    _active = active;
    DeviceProfile.setBackground(!active);
    if (active) {
      _scheduleAutoChecks();
      _scheduleSourceHealthChecks(initial: true);
    } else {
      _checkTimer?.cancel();
      _healthTimer?.cancel();
    }
  }

  /// Keeps every library work's list of readers fresh on its own, a few
  /// works at a time, without any visible loading.
  Future<void> _refreshStaleReaderLookups({int max = 2}) async {
    final stale = entries.where((e) => e.watch && e.work.type != ContentType.anime &&
        (e.webLookupAt == null ||
            DateTime.now().difference(e.webLookupAt!) > const Duration(days: 3)))
        .take(max)
        .toList();
    for (final e in stale) {
      if (!_active) return;
      await _backgroundWebLookup(e.work);
    }
  }

  void _scheduleAutoChecks() {
    _checkTimer?.cancel();
    if (!_active || settings.autoCheckMinutes <= 0 || !ready) return;
    // Recul en cas de problèmes réseau répétés, jusqu'à x8.
    final factor = 1 << (_consecutiveFailures.clamp(0, 3).toInt());
    _checkTimer = Timer(Duration(minutes: settings.autoCheckMinutes * factor), () async {
      if (_active && entries.any((e) => e.watch)) await checkUpdates();
      await _refreshStaleReaderLookups();
      if (_active) await refreshAnimePlanning();
      _scheduleAutoChecks();
    });
  }

  /// Verifie les sources pendant que l'application est ouverte. Aucun
  /// diagnostic HTTP ne prouve qu'un chapitre est lisible dans le lecteur.
  void _scheduleSourceHealthChecks({bool initial = false}) {
    _healthTimer?.cancel();
    if (!_active || !ready) return;
    _healthTimer = Timer(
      initial ? const Duration(seconds: 15) : const Duration(hours: 6),
      () async {
        if (_active) await checkSourceHealth();
        _scheduleSourceHealthChecks();
      },
    );
  }

  Future<void> checkSourceHealth({String? siteId, bool force = false}) async {
    if (checkingSources) return;
    // Never probe 200 third-party domains in the background. Automatic checks
    // cover the 13 original sources and individually registered user sources.
    // Directory entries can be checked explicitly, one at a time.
    final regularlyMonitoredIds = <String>{
      for (final site in catalogSites) site.id,
      for (final site in _userSources.where((s) => s.enabled)) site.id,
    };
    final candidates = activeSources.where((site) =>
        siteId != null ? site.id == siteId : regularlyMonitoredIds.contains(site.id))
        .where((site) => force || _sourceHealth[site.id] == null ||
            DateTime.now().difference(_sourceHealth[site.id]!.checkedAt) >=
                const Duration(hours: 6))
        .toList();
    if (candidates.isEmpty) return;
    checkingSources = true;
    notifyListeners();
    try {
      for (final site in candidates) {
        if (!_active) break;
        // Never declare a source dead from a single failed request.
        final recipe = _recipes.forSite(site.id);
        final probe = await _healthProbe.check(recipe.homeOverride ?? site.home);
        // A personal source may have been changed while this network request
        // was running. Never apply an old domain's probe to its replacement.
        final stillCurrent = activeSources.any((candidate) =>
            candidate.id == site.id && candidate.home == site.home);
        if (!stillCurrent) continue;
        _sourceHealth[site.id] = observeSourceHealth(
          site.id, _sourceHealth[site.id], probe,
        );
        lastHealthCheckAt = probe.checkedAt;
        notifyListeners();
      }
      try {
        await _sourceHealthStore?.save(_sourceHealth.values);
      } catch (e) {
        AppLog.error('Sauvegarde de la sante des sources', e);
      }
    } finally {
      checkingSources = false;
      notifyListeners();
    }
  }

  Future<CatalogSite> addPersonalSource({
    required String url,
    String name = '',
    List<String> languages = const ['fr', 'en'],
  }) async {
    if (_userSources.length >= UserSourceStore.maxSources) {
      throw const FormatException('250 sources personnelles maximum.');
    }
    final added = createUserSource(url: url, name: name, languages: languages);
    final existing = [
      ...catalogSites.map((s) => s.home),
      ..._directorySites.map((s) => s.home),
      ..._userSources.map((s) => s.url),
    ];
    if (existing.any((url) => normalizedSourceUri(url).toString() == added.url)) {
      throw const FormatException('Cette adresse figure deja dans les sources.');
    }
    final updated = [..._userSources, added];
    await _userSourceStore?.save(updated);
    _userSources..clear()..addAll(updated);
    notifyListeners();
    // First diagnosis without requiring a second user action. If another
    // batch is running, the next scheduled check will cover the new site.
    if (!checkingSources) {
      unawaited(checkSourceHealth(siteId: added.id, force: true));
    }
    return added.toCatalogSite();
  }

  Future<void> setPersonalSourceEnabled(String id, bool enabled) async {
    final index = _userSources.indexWhere((s) => s.id == id);
    if (index < 0) throw const FormatException('Cette source ne peut pas etre modifiee.');
    final updated = [..._userSources];
    updated[index] = updated[index].withEnabled(enabled);
    await _userSourceStore?.save(updated);
    _userSources..clear()..addAll(updated);
    notifyListeners();
  }

  /// Update a user-added source without changing its stable ID or deleting
  /// library entries. Domain changes are explicitly confirmed in the UI.
  /// An existing site link keeps its old URL until the user edits that link.
  Future<CatalogSite> updatePersonalSource({
    required String id,
    required String url,
    required String name,
    required List<String> languages,
  }) async {
    final index = _userSources.indexWhere((s) => s.id == id);
    if (index < 0) throw const FormatException('Source personnelle introuvable.');
    final updatedSite = _userSources[index].withDetails(
        url: url, name: name, languages: languages);
    final alreadyUsed = [
      ...catalogSites.map((s) => s.home),
      ..._directorySites.map((s) => s.home),
      ..._userSources.where((s) => s.id != id).map((s) => s.url),
    ];
    if (alreadyUsed.any((link) =>
        normalizedSourceUri(link).toString() == updatedSite.url)) {
      throw const FormatException('Cette adresse est deja utilisee.');
    }
    final changedUrl = _userSources[index].url != updatedSite.url;
    final staged = [..._userSources];
    staged[index] = updatedSite;
    await _userSourceStore?.save(staged);
    _userSources..clear()..addAll(staged);
    if (changedUrl) {
      _sourceHealth.remove(id); // Old domain's availability is not reusable.
      try {
        await _sourceHealthStore?.save(_sourceHealth.values);
      } catch (e) {
        AppLog.error('Sauvegarde de la sante apres changement de domaine', e);
      }
    }
    notifyListeners();
    if (changedUrl && updatedSite.enabled && !checkingSources) {
      unawaited(checkSourceHealth(siteId: id, force: true));
    }
    return updatedSite.toCatalogSite();
  }

  DateTime _lastSave = DateTime(2000);

  /// Saves 1 s after the last change, and at least every 8 s while changes
  /// keep coming (background refresh): no endless re-writing of a big
  /// library, nothing lost either.
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    final overdue = DateTime.now().difference(_lastSave) > const Duration(seconds: 8);
    _saveTimer = Timer(overdue ? const Duration(milliseconds: 200) : const Duration(seconds: 1), () {
      _lastSave = DateTime.now();
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(_data);
    } catch (e, st) {
      AppLog.error('Enregistrement de la bibliothèque', e, st);
    }
  }

  /// À appeler quand l'app passe en arrière-plan ou se ferme.
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _saveNow();
    }
  }

  // Public site searches are opt-in, not 200 automatic HTTP requests.
  // Search failures are visible instead of being interpreted as no manga.
  final Map<String, String> publicSearchStatus = {};
  int _publicSearchGeneration = 0;

  // -------------------------------------------------------------------------
  // Recherche et chapitres
  // -------------------------------------------------------------------------

  /// Recherche sur TOUTES les sources : connecteurs intégrés, extensions et
  /// chaque site du répertoire (plus de 200), sans sélection préalable.
  /// [selectedWebSites] est conservé pour compatibilité mais ignoré.
  Future<List<WorkInfo>> search(String query, {
    List<String> selectedWebSites = const [],
  }) => searchEverywhere(query);

  /// Progression de la dernière recherche multisource (affichée en direct).
  SearchProgress searchProgress = const SearchProgress();

  /// Every directory site that can be queried in the user's languages,
  /// excluding hosts already covered by a dedicated connector.
  bool isSourceBlocked(String sourceId) => settings.blockedSources.contains(sourceId);

  /// Excludes a source everywhere (search, chapters, reading, planning) and
  /// forgets the chapters it provided.
  void blockSource(String sourceId) {
    if (isSourceBlocked(sourceId)) return;
    updateSettings((s) => s.blockedSources = [...s.blockedSources, sourceId]);
    final name = sources.byId(sourceId)?.name;
    if (name != null) {
      _data.updates.removeWhere((u) => u.group == name && u.siteId == null);
    }
    for (final id in _chapterCache.keys.toList()) {
      if (_chapterCache[id]!.any((c) => c.sourceId == sourceId)) {
        _chapterCache.remove(id);
        _chapterCachedAt.remove(id);
        _readerRevision[id] = (_readerRevision[id] ?? 0) + 1;
      }
    }
    _changed();
  }

  void unblockSource(String sourceId) {
    updateSettings((s) => s.blockedSources =
        [for (final b in s.blockedSources) if (b != sourceId) b]);
    _chapterCache.clear();
    _chapterCachedAt.clear();
    notifyListeners();
  }

  /// Display name of a source id (blocked list, diagnostics).
  String sourceName(String sourceId) => sources.byId(sourceId)?.name ?? sourceId;

  List<PublicCatalogSource> webConnectors() {
    final langs = settings.comicLangs.toSet();
    final dedicated = <String>{
      'sushiscan.net', 'mangadex.org',
      for (final e in engine.extensions?.all ?? const <InstalledExtension>[])
        if (e.enabled) ...e.manifest.hosts,
    };
    final out = <PublicCatalogSource>[];
    final seen = <String>{};
    for (final site in activeSources) {
      if (site.hasReaderConnector) continue;
      if (!site.languages.any(langs.contains)) continue;
      final host = _normalizedHost(site.home);
      if (dedicated.contains(host) || !seen.add(host)) continue;
      final connector = _publicConnectorFor(site);
      if (isSourceBlocked(connector.id)) continue;
      out.add(connector);
    }
    return out;
  }

  /// Multisource search with bounded concurrency. [onUpdate] receives the
  /// merged results after each source, so the UI fills progressively.
  Future<List<WorkInfo>> searchEverywhere(String query, {
    void Function(List<WorkInfo> results, SearchProgress progress)? onUpdate,
    int concurrency = 10,
  }) async {
    final langs = settings.comicLangs.toSet();
    final q = query.trim();
    final native = sources.all.where((source) =>
      source.id != _captures.id && source is! PublicCatalogSource &&
      !isSourceBlocked(source.id)).toList();
    final web = q.length >= 2 ? webConnectors() : const <PublicCatalogSource>[];
    final all = <ContentSource>[...native, ...web];
    final generation = ++_publicSearchGeneration;
    final reports = <String, String>{};
    final results = <WorkInfo>[];
    var done = 0;
    var failed = 0;
    var progress = SearchProgress(total: all.length);
    searchProgress = progress;

    List<WorkInfo> merged() => mergeSearchResults([
      for (final work in results)
        if (work.languages.isEmpty || work.languages.any(langs.contains)) work,
    ]);

    var cursor = 0;
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    Future<void> worker() async {
      while (cursor < all.length) {
        if (generation != _publicSearchGeneration) return; // superseded
        final source = all[cursor++];
        try {
          final found = await source.search(q)
              .timeout(Duration(seconds: source is PublicCatalogSource ? 12 : 15));
          results.addAll(found);
          if (source is PublicCatalogSource) {
            reports[source.site.id] = found.isEmpty
                ? 'Aucune fiche correspondante'
                : '${found.length} fiche(s)';
          }
        } catch (e) {
          failed++;
          if (source is PublicCatalogSource) reports[source.site.id] = 'Échec : $e';
          AppLog.info('Recherche ${source.name} indisponible : $e');
        }
        done++;
        if (generation != _publicSearchGeneration) return;
        progress = SearchProgress(total: all.length, done: done, failed: failed,
            found: results.length);
        searchProgress = progress;
        final now = DateTime.now();
        if (done == all.length || now.difference(lastUpdate) > const Duration(milliseconds: 600)) {
          lastUpdate = now;
          onUpdate?.call(merged(), progress);
        }
      }
    }

    final workers = all.isEmpty ? 0 : concurrency.clamp(1, all.length).toInt();
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    if (generation == _publicSearchGeneration) {
      publicSearchStatus
        ..clear()
        ..addAll(reports);
    }
    if (all.isNotEmpty && failed == all.length && results.isEmpty) {
      throw const SourceException('Les moteurs de recherche ont tous échoué.');
    }
    return merged();
  }

  // Works from every site's home page (latest updates / popular). Cached.
  List<WorkInfo> _browseCache = const [];
  DateTime? _browseAt;
  bool browsing = false;
  SearchProgress browseProgress = const SearchProgress();

  List<WorkInfo> get browsedWorks => _browseCache;

  File? get _browseFile {
    final dir = _supportDir;
    return dir == null ? null : File('${dir.path}${Platform.pathSeparator}discover'
        '${Platform.pathSeparator}browse.json');
  }

  Future<void> _loadBrowseSnapshot() async {
    final file = _browseFile;
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['works'] is! List) return;
      final works = <WorkInfo>[];
      for (final w in raw['works'] as List) {
        if (w is Map) {
          try {
            works.add(WorkInfo.fromJson(w.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
      if (works.isEmpty || _browseCache.isNotEmpty) return;
      _browseCache = works;
      _browseAt = DateTime.tryParse('${raw['savedAt']}');
      notifyListeners();
    } catch (e) {
      AppLog.info('Découvrir : mémoire illisible ($e)');
    }
  }

  Future<void> _saveBrowseSnapshot() async {
    final file = _browseFile;
    if (file == null || _browseCache.isEmpty) return;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'works': [for (final w in _browseCache.take(3000)) w.toJson()],
      }));
      await tmp.rename(file.path);
    } catch (e) {
      AppLog.info('Découvrir : sauvegarde impossible ($e)');
    }
  }

  /// Fills « Découvrir » with the works shown on every site of the
  /// directory. The last result is shown instantly from disk; sites are
  /// re-read in background at most every 6 h. Metadata only.
  Future<void> browseEverywhere({bool force = false, int concurrency = 8}) async {
    if (browsing) return;
    if (_browseCache.isEmpty) await _loadBrowseSnapshot();
    final at = _browseAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(hours: 6) &&
        _browseCache.isNotEmpty) {
      return;
    }
    browsing = true;
    final sites = webConnectors();
    final found = <WorkInfo>[];
    var done = 0;
    var failed = 0;
    browseProgress = SearchProgress(total: sites.length);
    notifyListeners();
    var cursor = 0;
    var lastNotify = DateTime.now();
    final keepOld = _browseCache.isNotEmpty;
    Future<void> worker() async {
      while (cursor < sites.length) {
        final site = sites[cursor++];
        try {
          found.addAll(await site.browseLatest(limit: 24).timeout(const Duration(seconds: 12)));
        } catch (_) {
          failed++;
        }
        done++;
        browseProgress = SearchProgress(total: sites.length, done: done,
            failed: failed, found: found.length);
        // Few rebuilds: the grid is refreshed every 2 s, not per site. When
        // an older list is shown, it stays until the new one is complete.
        if (DateTime.now().difference(lastNotify) > const Duration(seconds: 2)) {
          lastNotify = DateTime.now();
          if (!keepOld) _browseCache = mergeSearchResults(found);
          notifyListeners();
        }
      }
    }
    try {
      final workers = sites.isEmpty ? 0 : concurrency.clamp(1, sites.length).toInt();
      await Future.wait([for (var i = 0; i < workers; i++) worker()]);
      if (found.isNotEmpty) {
        _browseCache = mergeSearchResults(found);
        _browseAt = DateTime.now();
        unawaited(_saveBrowseSnapshot());
      }
    } finally {
      browsing = false;
      notifyListeners();
    }
  }

  PublicCatalogSource _publicConnectorFor(CatalogSite site) {
    final key = 'public_${site.id}';
    final existing = sources.byId(key);
    if (existing is PublicCatalogSource) return existing;
    final adapter = PublicCatalogSource(site, http: engine.http);
    sources.register(adapter);
    return adapter;
  }

  /// Coalesce concurrent requests (rapid navigation, refresh and reader
  /// entry). Multiple linked catalogues are queried in parallel.
  Future<List<ChapterGroup>> chaptersFor(WorkInfo work, {bool refresh = false}) async {
    // Anime have episodes (AniList), not chapters: no site lookup at all.
    if (work.type == ContentType.anime) return const [];
    final active = _chapterLoads[work.id];
    if (active != null && (refresh || _chapterCache[work.id] == null)) return active;
    if (!refresh) {
      // Instant display: memory, then the snapshot saved on disk. The
      // network refresh runs silently and the page reloads by itself.
      var cached = _chapterCache[work.id];
      if (cached == null) {
        final snapshot = await _readChapterSnapshot(work.id);
        if (snapshot != null && _chapterCache[work.id] == null) {
          _chapterCache[work.id] = snapshot.$2;
          _chapterCachedAt[work.id] = snapshot.$1;
          cached = snapshot.$2;
        }
      }
      final age = _chapterCachedAt[work.id];
      if (cached != null && age != null) {
        if (DateTime.now().difference(age) > const Duration(minutes: 20)) {
          _silentChapterRefresh(work);
        }
        return groupChapters(cached);
      }
    }
    return _startChapterLoad(work);
  }

  void _silentChapterRefresh(WorkInfo work) {
    if (_chapterLoads.containsKey(work.id)) return;
    final before = _chapterSignature(_chapterCache[work.id]);
    _startChapterLoad(work).then((_) {
      if (_chapterSignature(_chapterCache[work.id]) != before) {
        _readerRevision[work.id] = readerRevision(work.id) + 1;
        notifyListeners();
      }
    }, onError: (Object e) {
      AppLog.info('Actualisation silencieuse de ${work.title} : $e');
    });
  }

  static String _chapterSignature(List<SourceChapter>? chapters) {
    if (chapters == null) return '';
    final ids = [for (final c in chapters) '${c.sourceId}|${c.chapterId}']..sort();
    return '${ids.length}:${ids.join(',').hashCode}';
  }

  /// Sites found for a work (library or not) survive a restart: coming
  /// back to a fiche shows its readers at once instead of searching again.
  File? get _locatedFile => _supportDir == null
      ? null
      : File('${_supportDir!.path}${Platform.pathSeparator}located-readers.json');

  Future<void> _loadLocatedReaders() async {
    final file = _locatedFile;
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      // v1 (2.3.6): {workId: [links]}; v2: {links, lookedUp, warmupAt}.
      final links = raw['version'] == 2 ? raw['links'] : raw;
      if (links is Map) {
        for (final e in links.entries) {
          if (e.value is! List) continue;
          _locatedReaderLinks[e.key as String] = [
            for (final l in e.value as List)
              if (l is Map) SourceLink.fromJson(Map<String, dynamic>.from(l)),
          ];
        }
      }
      final looked = raw['lookedUp'];
      if (looked is Map) {
        for (final e in looked.entries) {
          final d = DateTime.tryParse('${e.value}');
          if (d != null) _lookupDoneAt[e.key as String] = d;
        }
      }
      _warmupAt = DateTime.tryParse('${raw['warmupAt']}');
      _warmupVersion = raw['warmupVersion'] as String?;
      final votes = raw['statusVotes'];
      if (votes is Map) {
        for (final e in votes.entries) {
          if (e.value is Map) {
            _statusVotes['${e.key}'] = {
              for (final v in (e.value as Map).entries) '${v.key}': '${v.value}',
            };
          }
        }
      }
      final firstSeen = raw['firstSeen'];
      if (firstSeen is Map) {
        for (final e in firstSeen.entries) {
          if (e.value is Map) {
            _firstSeen['${e.key}'] = {
              for (final v in (e.value as Map).entries) '${v.key}': '${v.value}',
            };
          }
        }
      }
      lastCheckAt = DateTime.tryParse('${raw['lastCheckAt']}');
      final metaTried = raw['metaTried'];
      if (metaTried is Map) {
        for (final e in metaTried.entries) {
          final d = DateTime.tryParse('${e.value}');
          if (d != null) _metaTriedAt['${e.key}'] = d;
        }
      }
      final checked = raw['statusChecked'];
      if (checked is Map) {
        for (final e in checked.entries) {
          final d = DateTime.tryParse('${e.value}');
          if (d != null) _statusCheckedAt['${e.key}'] = d;
        }
      }
    } catch (e) {
      AppLog.info('Lecteurs trouvés non relus : $e');
    }
  }

  Future<void>? _locatedSaving;

  // ------------------------------------------------------------ statuses

  /// Status read on each source, per work: {source name: label}.
  final Map<String, Map<String, String>> _statusVotes = {};

  /// Last AniList status check per work.
  final Map<String, DateTime> _statusCheckedAt = {};

  void _recordStatusVote(String workId, String source, String label) {
    final votes = _statusVotes.putIfAbsent(workId, () => {});
    if (votes[source] == label) return;
    votes[source] = label;
    unawaited(_saveLocatedReaders());
  }

  /// Real status of a series: AniList, MangaDex, every site's work page
  /// (weights 3 / 2 / 1), then the date of the last chapter seen anywhere.
  SeriesStatusDecision seriesStatus(WorkInfo work) {
    final entry = _data.entries[work.id];
    final votes = <StatusVote>[
      for (final w in {work, if (entry != null) entry.work})
        if (w.publicationStatus != null)
          StatusVote(w.id.startsWith('anilist') ? 'AniList' : 'fiche',
              WorkStatusEngine.parse(w.publicationStatus), 2),
      for (final v in (_statusVotes[work.id] ?? const <String, String>{}).entries)
        StatusVote(v.key, WorkStatusEngine.parse(v.value),
            v.key == 'AniList' ? 3 : (v.key == 'MangaUpdates' ? 2 : 1)),
    ];
    // Real activity, from the most reliable evidence:
    // 1. date of the NEWEST chapter (any source) — if the newest one has no
    //    date, older dates prove nothing (a series that resumed 5 days ago
    //    on an undated site must not look paused);
    // 2. a new chapter seen by the app (notification);
    // 3. the « latest updates » feeds of the sites (planning history).
    DateTime? last;
    var newestUndated = false;
    void see(DateTime? d) {
      if (d != null && !d.isAfter(DateTime.now()) && (last == null || d.isAfter(last!))) last = d;
    }
    final chapters = _chapterCache[work.id] ?? const <SourceChapter>[];
    double? newest;
    for (final c in chapters) {
      final n = c.key.number;
      if (n != null && (newest == null || n > newest)) newest = n;
    }
    if (newest != null) {
      final top = [for (final c in chapters) if (c.key.number == newest) c];
      final dated = [for (final c in top) if (c.publishedAt != null) c.publishedAt!];
      if (dated.isEmpty) {
        newestUndated = true;
      } else {
        dated.sort();
        see(dated.first);
      }
    }
    for (final u in _data.updates) {
      if (u.workId == work.id) see(u.publishedAt ?? u.foundAt);
    }
    see(schedule.lastSeenRelease([work.title, ...work.altTitles]));
    if (last == null && !newestUndated) {
      for (final list in entry?.releaseDates.values ?? const <List<String>>[]) {
        for (final raw in list) {
          see(DateTime.tryParse(raw)?.toLocal());
        }
      }
    }
    return WorkStatusEngine.decide(votes, lastRelease: last,
        lastReleaseIsNewest: !newestUndated);
  }

  /// AniList status of the library works (checked every 3 days, a few
  /// works per run). Metadata only.
  Future<void> refreshSeriesStatuses({int max = 40, DateTime? deadline}) async {
    var n = 0;
    for (final e in entries.toList()) {
      if (n >= max || (deadline != null && DateTime.now().isAfter(deadline))) break;
      if (e.work.type == ContentType.anime) continue;
      bool due(String key) {
        final at = _statusCheckedAt[key];
        return at == null || DateTime.now().difference(at) >= const Duration(days: 3);
      }
      final aniList = due(e.work.id);
      final mu = due('mu:${e.work.id}');
      if (!aniList && !mu) continue;
      n++;
      if (aniList) {
        try {
          final hits = await anilist.comicCatalog(search: e.work.title, perPage: 5,
              sort: 'SEARCH_MATCH').timeout(const Duration(seconds: 10));
          final same = hits.where((w) => sameWorkAcrossSources(e.work, w)).toList();
          if (same.isNotEmpty && same.first.publicationStatus != null) {
            _recordStatusVote(e.work.id, 'AniList', same.first.publicationStatus!);
          }
          _statusCheckedAt[e.work.id] = DateTime.now();
        } catch (_) {
          // AniList busy (429): next run.
        }
      }
      if (mu) {
        await _checkMangaUpdates(e);
        _statusCheckedAt['mu:${e.work.id}'] = DateTime.now();
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    unawaited(_saveLocatedReaders());
  }

  late final MangaUpdatesClient mangaUpdates = MangaUpdatesClient(engine.http);

  /// MangaUpdates: official status + real dates of the past chapters (every
  /// scanlation group). The dates feed the planning rhythm of the work
  /// (« tous les 7 j, le samedi ») when the sites of the library gave few.
  Future<void> _checkMangaUpdates(LibraryEntry e) async {
    try {
      final id = await mangaUpdates.findSeries([e.work.title, ...e.work.altTitles])
          .timeout(const Duration(seconds: 20));
      if (id == null) return;
      final status = await mangaUpdates.status(id).timeout(const Duration(seconds: 15));
      if (status != null) _recordStatusVote(e.work.id, 'MangaUpdates', status);
      final dates = await mangaUpdates.chapterDates(id).timeout(const Duration(seconds: 15));
      // Only the newest chapters: their release day, one date per chapter.
      final recent = dates.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final picked = [for (final d in recent.take(12)) d.value];
      if (picked.length >= 3) {
        final merged = ReleasePlanner.addDates(e.releaseDates['en'] ?? const [], picked);
        if (merged.join() != (e.releaseDates['en'] ?? const []).join()) {
          e.releaseDates['en'] = merged;
          _changed();
        }
      }
      AppLog.info('MangaUpdates · ${e.work.title} : statut ${status ?? '?'}, '
          '${dates.length} chapitres datés');
    } catch (err) {
      AppLog.info('MangaUpdates · ${e.work.title} : indisponible ($err)');
    }
  }

  /// When the 200+ sites were last searched for a work (kept on disk).
  final Map<String, DateTime> _lookupDoneAt = {};

  /// Last full start-up update (splash).
  DateTime? _warmupAt;

  /// Version of the app at the last start-up update: a new version may read
  /// catalogues the previous one could not, so failed sites are retried.
  String? _warmupVersion;

  bool _crawling = false;

  /// Reads the catalogue (all series titles) of every site, 12 at a time,
  /// and keeps it on disk. Sites indexed less than [maxAge] ago are
  /// skipped; sites that failed are retried after 6 h. Stops at [deadline]
  /// (the rest continues on the next call).
  Future<void> crawlSiteIndex({
    void Function(String step)? onStep,
    DateTime? deadline,
    Duration maxAge = const Duration(days: 3),
  }) async {
    if (_crawling) return;
    _crawling = true;
    try {
      await _indexLoading;
      final now = DateTime.now();
      final todo = webConnectors().where((s) {
        if (siteIndex.isFresh(s.id, maxAge: maxAge)) return false;
        final failed = siteIndex.failedAt[s.id];
        // A site that could not be read (dead, anti-robot…) is retried
        // after 2 days, not at every start.
        return failed == null || now.difference(failed) > const Duration(days: 2);
      }).toList()
        // Never indexed first, then the oldest.
        ..sort((a, b) => (siteIndex.crawledAt[a.id] ?? DateTime(2000))
            .compareTo(siteIndex.crawledAt[b.id] ?? DateTime(2000)));
      if (todo.isEmpty) return;
      var cursor = 0;
      var done = 0;
      var ok = 0;
      final failures = <String, String>{};
      indexProgress = SearchProgress(total: todo.length);
      void report() {
        indexProgress = SearchProgress(total: todo.length, done: done, found: ok);
        onStep?.call('Catalogues des sites · $done/${todo.length} · '
            '${siteIndex.titleCount} titres');
      }
      report();
      Future<void> worker() async {
        while (cursor < todo.length &&
            (deadline == null || DateTime.now().isBefore(deadline))) {
          final site = todo[cursor++];
          await _breathe();
          try {
            final titles = await site.catalogueTitles()
                .timeout(const Duration(seconds: 90));
            if (titles.isEmpty) {
              siteIndex.fail(site.id);
              failures[site.name] = site.catalogueFailure ?? 'aucune série trouvée';
            } else {
              await siteIndex.put(site.id, titles);
              ok++;
            }
          } catch (e) {
            siteIndex.fail(site.id);
            failures[site.name] = '$e';
          }
          done++;
          report();
          if (done % 25 == 0) notifyListeners();
          if (done % 25 == 0 && !reading) unawaited(siteIndex.save());
        }
      }
      await Future.wait([for (var i = 0; i < DeviceProfile.crawlWorkers; i++) worker()]);
      await siteIndex.save();
      AppLog.info('Index des sites : $ok/$done catalogues lus, '
          '${siteIndex.siteCount} sites, ${siteIndex.titleCount} titres.');
      // Why each catalogue could not be read (one line per site).
      for (final f in failures.entries) {
        AppLog.info('Catalogue non lu — ${f.key} : ${f.value}');
      }
    } finally {
      _crawling = false;
      indexProgress = null;
      notifyListeners();
    }
  }

  /// Start-up update shown on the splash, so that the app is then fluid:
  /// first launch = everything (releases + chapter lists of the library);
  /// after a few hours away = the same, shorter thanks to the cache;
  /// otherwise nothing (instant start). The rest refreshes in background.
  /// [onSplash]: run while the splash screen is shown (light mode). The
  /// library's chapters are refreshed there in one go (at most 45 s, lists
  /// less than 12 h old kept as they are); the sites' catalogues are only
  /// read there the very first time, otherwise later when the app is idle.
  Future<void> warmUp({void Function(String step)? onStep, bool onSplash = false}) async {
    _splashWork = onSplash;
    try {
      await _warmUp(onStep: onStep, onSplash: onSplash);
    } finally {
      _splashWork = false;
    }
  }

  Future<void> _warmUp({void Function(String step)? onStep, bool onSplash = false}) async {
    if (!ready) return;
    // New versions are looked for at once, not after the warm-up.
    await _checkFailedInstall();
    _startOnlineWatch();
    _scheduleUpdateChecks();
    await _indexLoading;
    // No catalogue indexed yet = first full loading (up to ~5 min).
    final upgraded = _warmupVersion != appVersion;
    if (upgraded) siteIndex.failedAt.clear();
    // Full loading only the very first time; a new version of Pazulu keeps
    // what is already known (chapter lists on disk, sites found).
    // (Not « never finished »: closing Pazulu during the first loading must
    // not make every later start a full loading again — what was read is
    // already on disk.)
    final first = siteIndex.siteCount == 0;
    final start = DateTime.now();
    final end = start.add(first
        ? const Duration(minutes: 5)
        : (onSplash ? const Duration(seconds: 45) : const Duration(seconds: 90)));
    final works = [
      for (final e in entries)
        if (e.work.type != ContentType.anime) e.work,
    ];
    try {
      // 1. Catalogues of every site: all of them the first time, then only
      // those older than 24 h (the rest continues in background).
      if (first || !onSplash) {
        await crawlSiteIndex(onStep: onStep,
            deadline: first ? start.add(const Duration(minutes: 3)) : start.add(const Duration(seconds: 30)));
      }
      // 2. Chapters of EVERY library work from all its sites. The lists
      // already on disk less than an hour old are kept as they are: later
      // starts only fetch what changed.
      final queue = <WorkInfo>[];
      final entryOf = {for (final e in entries) e.work.id: e};
      for (final w in works) {
        final snap = _chapterCache[w.id] == null ? await _readChapterSnapshot(w.id) : null;
        if (snap != null) {
          _chapterCache[w.id] = snap.$2;
          _chapterCachedAt[w.id] = snap.$1;
        }
        final age = _chapterCachedAt[w.id];
        // Lists on disk less than 6 h old are kept as they are (12 h on a
        // modest PC): a restart only refreshes what may have changed. Works
        // not being read (finished, paused, dropped, untouched for 2
        // months): every 3 days only.
        final e = entryOf[w.id];
        final recentlyRead = e != null &&
            DateTime.now().difference(e.progress.updatedAt ?? e.addedAt) < const Duration(days: 60);
        final current = e == null ||
            (e.status == TrackStatus.reading || e.status == TrackStatus.planned) && recentlyRead;
        final maxAge = !current
            ? const Duration(days: 3)
            : (DeviceProfile.light ? const Duration(hours: 12) : const Duration(hours: 6));
        if (age == null || DateTime.now().difference(age) > maxAge) {
          queue.add(w);
        }
      }
      var done = 0;
      late final int total;
      // Works being read first (most recent progress), then the others.
      final recent = {
        for (final e in entries) e.work.id: e.progress.updatedAt ?? e.addedAt,
      };
      queue.sort((a, b) => (recent[a.id] ?? DateTime(2000)).compareTo(recent[b.id] ?? DateTime(2000)));
      // At most 60 works per start (30 on a modest PC), the most recently
      // read: a big library is refreshed over several starts instead of all
      // at once; any work is refreshed anyway when its fiche is opened.
      final cap = DeviceProfile.light ? 30 : 60;
      if (queue.length > cap) queue.removeRange(0, queue.length - cap);
      total = queue.length;
      onStep?.call('Chapitres de la bibliothèque · 0/$total');
      chapterGate.perLane = DeviceProfile.enginesPerLanguage;
      _chapterSourceTimeout = const Duration(seconds: 20);
      Future<void> worker() async {
        while (queue.isNotEmpty && DateTime.now().isBefore(end)) {
          await _breathe();
          final w = queue.removeLast();
          try {
            await chaptersFor(w, refresh: true).timeout(const Duration(seconds: 30));
          } catch (_) {
            // Kept from the previous list; the start-up never blocks on one site.
          }
          done++;
          onStep?.call('Chapitres de la bibliothèque · $done/$total');
        }
      }
      final chaptersStart = DateTime.now();
      try {
        await Future.wait([for (var i = 0; i < DeviceProfile.chapterWorkers; i++) worker()]);
      } finally {
        _chapterSourceTimeout = const Duration(seconds: 45);
      }
      AppLog.info('Chapitres de la bibliothèque : $done/$total en '
          '${DateTime.now().difference(chaptersStart).inSeconds} s '
          '(${DeviceProfile.enginesPerLanguage} moteurs FR + ${DeviceProfile.enginesPerLanguage} EN, '
          '${DeviceProfile.requestsPerSite} requêtes max par site).');
      // 3. New chapters (notifications) from the lists just loaded.
      // Not again if done less than 3 h ago (the hourly check continues).
      final recentCheck = lastCheckAt != null &&
          DateTime.now().difference(lastCheckAt!) < const Duration(hours: 3);
      if (settings.checkOnStartup && !recentCheck && entries.any((e) => e.watch) &&
          DateTime.now().isBefore(end)) {
        onStep?.call('Recherche des nouveaux chapitres…');
        await checkUpdates().timeout(end.difference(DateTime.now()), onTimeout: () => 0);
      }
      // 4. Status of each series (AniList + sites + activity) for the planning.
      if (DateTime.now().isBefore(end)) {
        onStep?.call('Statut des séries (en cours, pause, terminée)…');
        await refreshSeriesStatuses(deadline: end);
      }
    } catch (e) {
      AppLog.info('Mise à jour au démarrage incomplète : $e');
    }
    _warmupAt = DateTime.now();
    _warmupVersion = appVersion;
    unawaited(_saveLocatedReaders());
    // What did not fit continues in background, the app is usable.
    Timer(const Duration(seconds: 20), () => unawaited(crawlSiteIndex()));
    Timer(const Duration(minutes: 2), () => unawaited(refreshSeriesStatuses()));
    AppLog.info('Démarrage : ${works.length} œuvres, '
        '${DateTime.now().difference(start).inSeconds} s (${first ? 'premier chargement complet' : 'mise à jour'}).');
  }

  Future<void> _saveLocatedReaders() async {
    // Coalesced: one write at a time, the last state wins.
    while (_locatedSaving != null) {
      await _locatedSaving;
    }
    final file = _locatedFile;
    if (file == null) return;
    final job = () async {
      try {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'version': 2,
          'links': {
            for (final e in _locatedReaderLinks.entries)
              e.key: [for (final l in e.value) l.toJson()],
          },
          'lookedUp': {
            for (final e in _lookupDoneAt.entries) e.key: e.value.toIso8601String(),
          },
          if (_warmupAt != null) 'warmupAt': _warmupAt!.toIso8601String(),
          if (_warmupVersion != null) 'warmupVersion': _warmupVersion,
          'statusVotes': _statusVotes,
          'firstSeen': _firstSeen,
          if (lastCheckAt != null) 'lastCheckAt': lastCheckAt!.toIso8601String(),
          'metaTried': {
            for (final e in _metaTriedAt.entries) e.key: e.value.toIso8601String(),
          },
          'statusChecked': {
            for (final e in _statusCheckedAt.entries) e.key: e.value.toIso8601String(),
          },
        }), flush: true);
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      } catch (e) {
        AppLog.info('Lecteurs trouvés non enregistrés : $e');
      }
    }();
    _locatedSaving = job;
    try {
      await job;
    } finally {
      _locatedSaving = null;
    }
  }

  File? _snapshotFile(String workId) {
    final dir = _supportDir;
    if (dir == null) return null;
    final name = sha256.convert(utf8.encode(workId)).toString().substring(0, 24);
    return File('${dir.path}${Platform.pathSeparator}chapters'
        '${Platform.pathSeparator}$name.json');
  }

  Future<(DateTime, List<SourceChapter>)?> _readChapterSnapshot(String workId) async {
    final file = _snapshotFile(workId);
    if (file == null || !await file.exists()) return null;
    try {
      // Read and decoded outside the screen's thread when it is big (long
      // series from many sites): a large library no longer freezes the app.
      final path = file.path;
      final size = await file.length();
      return size > 48 * 1024
          ? await Isolate.run(() => _decodeChapterSnapshot(File(path).readAsStringSync(), workId))
          : _decodeChapterSnapshot(await file.readAsString(), workId);
    } catch (_) {
      return null;
    }
  }

  static (DateTime, List<SourceChapter>)? _decodeChapterSnapshot(String text, String workId) {
    final raw = jsonDecode(text);
    if (raw is! Map || raw['workId'] != workId || raw['chapters'] is! List) return null;
    final at = DateTime.tryParse('${raw['savedAt']}');
    if (at == null) return null;
    final list = [
      for (final c in raw['chapters'] as List)
        if (SourceChapter.fromJson(c) case final SourceChapter ok) ok,
    ];
    return list.isEmpty ? null : (at, list);
  }

  Future<void> _writeChapterSnapshot(String workId, List<SourceChapter> chapters) async {
    final file = _snapshotFile(workId);
    if (file == null || chapters.isEmpty) return;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'workId': workId,
        'savedAt': DateTime.now().toIso8601String(),
        'chapters': [for (final c in chapters) c.toJson()],
      }), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      AppLog.info('Instantané des chapitres non enregistré : $e');
    }
  }

  Future<List<ChapterGroup>> _startChapterLoad(WorkInfo work) {
    final active = _chapterLoads[work.id];
    if (active != null) return active;
    final future = _fetchChapters(work);
    _chapterLoads[work.id] = future;
    future.whenComplete(() {
      if (identical(_chapterLoads[work.id], future)) {
        _chapterLoads.remove(work.id);
      }
    }).ignore();
    return future;
  }

  /// Shared by every engine: a French team and an English team (8 engines
  /// each, they help each other), never more than 2 requests at once on a
  /// site.
  final HostGate chapterGate = HostGate(
      perSite: DeviceProfile.requestsPerSite, perLane: DeviceProfile.enginesPerLanguage);

  /// « fr » for a French-only site, « en » otherwise.
  String _laneOf(ContentSource source) {
    final langs = source is PublicCatalogSource ? source.site.languages : const <String>[];
    return langs.isNotEmpty && langs.every((l) => l == 'fr') ? 'fr' : 'en';
  }

  /// Shorter wait per site while the library refreshes in background: a
  /// slow site keeps its previous list and is asked again next time.
  Duration _chapterSourceTimeout = const Duration(seconds: 45);

  Future<List<ChapterGroup>> _fetchChapters(WorkInfo work) async {
    // Every source (integrated connectors AND every directory site, all at
    // the same level) is searched in background for this work; found
    // readers are attached and the chapter list refreshes by itself.
    unawaited(_backgroundWebLookup(work));
    final links = <String, SourceLink>{
      for (final link in [
        ...work.links,
        ...?_data.entries[work.id]?.work.links,
        ...?_locatedReaderLinks[work.id],
        // Every site whose catalogue lists this title (local index): all
        // of them at once, no source before another.
        ...siteIndex.linksFor([work.title, ...work.altTitles]),
      ])
        if (!isSourceBlocked(link.sourceId)) '${link.sourceId}:${link.workId}': link,
    };
    final previous = _chapterCache[work.id] ?? const <SourceChapter>[];
    final successful = <String, List<SourceChapter>>{};
    final failed = <String>{};
    final checks = <CatalogueCheck>[];
    Object? lastSourceError;
    var successes = 0;

    Future<void> loadNative(SourceLink link) async {
      final source = sources.byId(link.sourceId);
      if (source == null) {
        checks.add(CatalogueCheck(sourceId: link.sourceId,
          name: link.sourceId, state: CatalogueCheckState.unsupported,
          observed: 0, readable: 0,
          detail: 'Aucun connecteur de chapitres installé.'));
        return;
      }
      try {
        final timeout = _chapterSourceTimeout;
        // The wait for a free engine is not counted, only the site's answer.
        final chapters = await chapterGate.run(source.id, () => source.listChapters(
          link.workId, langs: settings.comicLangs,
        ).timeout(timeout), lane: _laneOf(source));
        successes++;
        successful.putIfAbsent(source.id, () => <SourceChapter>[]).addAll(chapters);
        if (source is PublicCatalogSource) {
          final label = source.statusLabels[link.workId];
          if (label != null) _recordStatusVote(work.id, source.name, label);
        }
        checks.add(CatalogueCheck(sourceId: source.id, name: source.name,
          state: chapters.isEmpty ? CatalogueCheckState.empty : CatalogueCheckState.checked,
          observed: chapters.length,
          readable: chapters.where((c) => !c.isExternal).length,
          detail: 'Catalogue de cette source uniquement ; non exhaustif pour l’œuvre.'));
      } catch (e) {
        lastSourceError = e;
        failed.add(source.id);
        checks.add(CatalogueCheck(sourceId: source.id, name: source.name,
          state: CatalogueCheckState.failed, observed: 0, readable: 0,
          retained: previous.where((c) => c.sourceId == source.id).length,
          detail: '$e'));
        AppLog.info('Catalogue ${source.name} indisponible pour ${work.title}: $e');
      }
    }

    // Additional work pages *explicitly linked by the user* can contribute
    // public chapter indexes. They are listing-only, never image providers.
    Future<void> loadLinkedSite(SavedSiteLink link) async {
      final site = siteById(link.siteId);
      if (site == null || !site.accepts(link.url) ||
          !activeSources.any((s) => s.id == site.id) ||
          !settings.comicLangs.contains(link.lang) || site.hasReaderConnector) {
        return;
      }
      final hash = sha256.convert(utf8.encode(link.url)).toString().substring(0, 16);
      final sourceId = 'listing:${site.id}:$hash';
      if (!_recipes.forSite(site.id).canInspect) {
        checks.add(CatalogueCheck(sourceId: sourceId, name: site.title,
          state: CatalogueCheckState.unsupported, observed: 0, readable: 0,
          detail: 'Ce site conserve son lecteur officiel.'));
        return;
      }
      try {
        final listing = await _listingFetcher.fetch(site: site, workUrl: link.url);
        final chapters = ChapterListingParser.asChapters(listing,
          bucketId: sourceId, language: link.lang, label: site.title);
        successes++;
        successful[sourceId] = chapters;
        checks.add(CatalogueCheck(sourceId: sourceId, name: site.title,
          state: CatalogueCheckState.checked,
          observed: chapters.length, readable: 0,
          detail: 'Liste publique confirmée. Pages non récupérées : lecteur externe.'));
      } catch (e) {
        lastSourceError = e;
        failed.add(sourceId);
        checks.add(CatalogueCheck(sourceId: sourceId, name: site.title,
          state: CatalogueCheckState.failed, observed: 0, readable: 0,
          retained: previous.where((c) => c.sourceId == sourceId).length,
          detail: '$e'));
        AppLog.info('Liste publique de ${site.title} non vérifiable : $e');
      }
    }

    final linkedSites = <String, SavedSiteLink>{
      for (final link in _data.entries[work.id]?.savedSiteLinks ?? const <SavedSiteLink>[])
        '${link.siteId}:${link.lang}:${link.url}': link,
    }.values.take(8);
    await Future.wait(<Future<void>>[
      for (final link in links.values) loadNative(link),
      for (final link in linkedSites) loadLinkedSite(link),
    ]);

    final saved = downloadsFor(work.id).map((r) => r.toChapter())
        .where((c) => !isSourceBlocked(c.sourceId)).toList();
    // ALL SOURCES ARE PEERS. No connector (MangaDex or any other) is a
    // reference: each list is checked against what all the OTHER sources
    // say. A list is refused only when it contradicts its peers (another
    // series, a home page of « latest updates »…) — never because it has
    // more chapters than one particular source.
    List<SourceChapter> peersOf(String sourceId) => [
      for (final pair in successful.entries)
        if (pair.key != sourceId && !ListingGuard.looksMixed(pair.value)) ...pair.value,
      for (final c in saved)
        if (c.sourceId != sourceId) c,
    ];
    // Integrated connectors (MangaDex, SushiScan…) read ONE series by its
    // id: their list cannot be « several works mixed ». Only web sites
    // (redirect to a home page, wrong search hit) are checked this way.
    // 2.3.7 detached SushiScan from Solo Leveling (volumes, then ch. 0 and
    // 179.5–200) and deleted its offline copies.
    bool exactSeries(String id) {
      final s = sources.byId(id);
      return s != null && s is! PublicCatalogSource;
    }
    final origin = <String>{
      for (final l in work.links.take(1)) l.sourceId,
      for (final l in (_data.entries[work.id]?.work.links ?? const <SourceLink>[]).take(1))
        l.sourceId,
    };
    // Offline copies are checked the same way (a copy made from a wrongly
    // attached site — chapter 3861 of another series — is removed).
    final badDownloads = <SourceChapter>[];
    final bySavedSource = <String, List<SourceChapter>>{};
    for (final c in saved) {
      if (c.sourceId.startsWith('local') || c.sourceId == _captures.id) continue;
      bySavedSource.putIfAbsent(c.sourceId, () => []).add(c);
    }
    for (final pair in bySavedSource.entries) {
      if (exactSeries(pair.key)) continue;
      final peers = peersOf(pair.key);
      final combined = [...pair.value, ...?successful[pair.key]];
      if (ListingGuard.rejectReason(combined, peers) != null) {
        badDownloads.addAll(pair.value);
      } else {
        for (final c in pair.value) {
          if (_outlier(c, peers)) badDownloads.add(c);
        }
      }
    }
    if (badDownloads.isNotEmpty) {
      final badIds = {for (final c in badDownloads) c.chapterId};
      saved.removeWhere((c) => badIds.contains(c.chapterId));
      for (final c in badDownloads) {
        AppLog.info('Copie hors ligne incohérente retirée de ${work.title} : '
            '${c.key.longLabel} (${c.sourceId})');
        unawaited(deleteDownload(c.chapterId));
      }
    }
    final rejected = <String, String>{};
    // Each other source's list on its own (to compare with the most
    // advanced one, not with a mix).
    List<List<SourceChapter>> otherLists(String sourceId) {
      final bySaved = <String, List<SourceChapter>>{};
      for (final c in saved) {
        if (c.sourceId != sourceId) bySaved.putIfAbsent(c.sourceId, () => []).add(c);
      }
      return [
        for (final pair in successful.entries)
          if (pair.key != sourceId && !ListingGuard.looksMixed(pair.value)) pair.value,
        ...bySaved.values,
      ];
    }
    // Vote between ALL the lists (connectors and saved copies vote too, but
    // are never rejected): a minority far above the others is another work
    // of the same name (a novel, a fan series).
    final byList = <String, List<SourceChapter>>{
      for (final pair in successful.entries)
        if (!ListingGuard.looksMixed(pair.value)) pair.key: pair.value,
    };
    for (final c in saved) {
      if (!successful.containsKey(c.sourceId)) byList.putIfAbsent('saved:${c.sourceId}', () => []).add(c);
    }
    // A site that did not answer this time is judged on its previous list.
    for (final c in previous) {
      if (failed.contains(c.sourceId) && !successful.containsKey(c.sourceId)) {
        byList.putIfAbsent(c.sourceId, () => []).add(c);
      }
    }
    final minority = ListingGuard.minorityLevels(byList,
        siteOf: (id) => (sources.byId(id)?.name ?? id).toLowerCase(),
        protect: {
          ...origin,
          for (final id in byList.keys)
            if (id.startsWith('saved:') || exactSeries(id)) id,
        });
    for (final pair in successful.entries.toList()) {
      if (exactSeries(pair.key)) continue;
      final reason = ListingGuard.rejectReason(pair.value, peersOf(pair.key)) ??
          minority[pair.key] ??
          (origin.contains(pair.key)
              ? null
              : ListingGuard.farBeyondAllPeers(pair.value, otherLists(pair.key)));
      if (reason == null) continue;
      if (origin.contains(pair.key)) {
        // The page the user opened is kept, only its foreign chapters go.
        final peers = peersOf(pair.key);
        successful[pair.key] = [
          for (final c in pair.value) if (!_outlier(c, peers)) c,
        ];
        continue;
      }
      rejected[pair.key] = reason;
    }
    // A source that failed now must not keep stale foreign chapters.
    for (final id in failed) {
      if (origin.contains(id) || exactSeries(id)) continue;
      final stale = previous.where((c) => c.sourceId == id).toList();
      final reason = ListingGuard.rejectReason(stale, peersOf(id)) ?? minority[id];
      if (reason != null) rejected[id] = reason;
    }
    if (rejected.isNotEmpty || badDownloads.isNotEmpty) {
      final badKeys = <String>{
        for (final c in badDownloads) c.key.id,
        for (final id in rejected.keys) ...?successful[id]?.map((c) => c.key.id),
        for (final c in previous)
          if (rejected.containsKey(c.sourceId)) c.key.id,
      };
      for (final id in rejected.keys) {
        successful.remove(id);
        failed.remove(id);
        checks.removeWhere((c) => c.sourceId == id);
        checks.add(CatalogueCheck(sourceId: id, name: sources.byId(id)?.name ?? id,
            state: CatalogueCheckState.failed, observed: 0, readable: 0,
            detail: 'Rattachement retiré : ${rejected[id]}.'));
        AppLog.info('Lecteur $id détaché de ${work.title} : ${rejected[id]}');
      }
      _detachSources(work.id, {
        ...rejected.keys,
        for (final c in badDownloads)
          if (!(successful[c.sourceId]?.isNotEmpty ?? false) && !origin.contains(c.sourceId))
            c.sourceId,
      }, badKeys: badKeys,
          clean: [for (final list in successful.values) ...list, ...saved]);
    }
    final previousClean = [
      for (final c in previous)
        if (!rejected.containsKey(c.sourceId)) c,
    ];
    final merged = mergeObservedChapters(
      previous: previousClean, successful: successful, failed: failed, local: saved);
    // Same numbering check for every work: agreement between all sources.
    final (all, consensusNotes) = ChapterConsensus.apply(merged);
    _unconfirmedAhead[work.id] = ChapterConsensus.unconfirmedAhead(all);
    // First time a chapter appears anywhere (only after a first complete
    // list, so old chapters never get « today »): its release date when no
    // site writes one.
    if (previous.isNotEmpty) {
      final before = {for (final c in previous) '${c.lang}|${c.key.id}'};
      final seen = _firstSeen.putIfAbsent(work.id, () => {});
      var added = false;
      for (final c in all) {
        final k = '${c.lang}|${c.key.id}';
        if (c.isExternal || before.contains(k) || seen.containsKey(k)) continue;
        seen[k] = DateTime.now().toIso8601String();
        added = true;
      }
      if (seen.length > 80) {
        final keep = (seen.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(80);
        _firstSeen[work.id] = {for (final e in keep) e.key: e.value};
      }
      if (added) unawaited(_saveLocatedReaders());
    }
    for (final note in consensusNotes) {
      if (_consensusLogged.add('${work.id}|${note.sourceId}|${note.message}')) {
        AppLog.info('Numérotation ${work.title} — ${sourceName(note.sourceId)} : ${note.message}');
      }
    }
    final readable = all.where((c) => !c.isExternal).length;
    // Nothing readable (the attached sources failed, or have no chapter in
    // the reading languages): every source is searched NOW, with progress,
    // and the list is rebuilt with what they found. Once per session/work.
    if (readable == 0 && _foregroundLookup.add(work.id)) {
      try {
        final report = await locateNativeReaders(work, showProgress: true)
            .timeout(const Duration(seconds: 45));
        if (report.found > 0) return await _fetchChapters(work);
      } catch (e) {
        AppLog.info('Recherche de lecteurs pour ${work.title} : $e');
      }
    }
    if (successes == 0 && saved.isEmpty && previous.isEmpty &&
        lastSourceError != null) {
      _catalogueChecks[work.id] = checks;
      throw SourceException('Aucune des ${links.length} source(s) liée(s) n\'a répondu et '
          'aucun autre site n\'a été trouvé pour le moment. Dernière erreur : $lastSourceError');
    }
    // Holes (199 → 261) or fewer chapters than announced: other sites
    // certainly have them, search now instead of waiting.
    // Also when a reading language has nothing yet (Overgeared: FR only)
    // or when fewer than 3 sites offer the work: every site is searched,
    // none is a reference.
    final readableSources = <String>{
      for (final c in all) if (!c.isExternal) c.sourceId,
    };
    final missingLang = settings.comicLangs.any((l) =>
        !all.any((c) => !c.isExternal && c.lang == l));
    if (Coverage.incomplete(all, lastChapter: work.lastChapter) || successes == 0 ||
        readable == 0 || missingLang || readableSources.length < 3) {
      unawaited(_backgroundWebLookup(work, urgent: true));
    }
    // A notification for a chapter that no source lists any more in that
    // language (a FR chapter that was in fact locked / premium, a wrong
    // match) is withdrawn — only when every source answered.
    final unconfirmed = LanguageConsensus.unconfirmed(all);
    _unconfirmedLang[work.id] = unconfirmed;
    if (successes > 0 && failed.isEmpty) {
      final present = {
        for (final c in all)
          if (!unconfirmed.contains(c.chapterId)) '${c.key.id}|${c.lang}',
      };
      final before = _data.updates.length;
      _data.updates.removeWhere((u) =>
          u.workId == work.id && u.siteId == null &&
          !present.contains('${u.keyId}|${u.lang}'));
      if (_data.updates.length != before) _changed();
    }
    _catalogueChecks[work.id] = checks;
    final changed = _chapterSignature(_chapterCache[work.id]) != _chapterSignature(all);
    _chapterCache[work.id] = all;
    if (changed) {
      // Any open fiche shows the complete list at once (no need to leave
      // and come back).
      _readerRevision[work.id] = readerRevision(work.id) + 1;
      notifyListeners();
    }
    _chapterCachedAt[work.id] = DateTime.now();
    // Every visited work (library or not): coming back is instant.
    unawaited(_writeChapterSnapshot(work.id, all));
    return groupChapters(all);
  }

  final Set<String> _foregroundLookup = {};

  /// Chapter ids whose language is claimed by a single source ahead of all
  /// the others (shown « FR ? », never announced as a release).
  final Map<String, Set<String>> _unconfirmedLang = {};

  bool isLangUnconfirmed(String workId, String chapterId) =>
      _unconfirmedLang[workId]?.contains(chapterId) ?? false;

  /// Explicit metadata-only source search. Does NOT fetch any chapter pages,
  /// and never guesses an edition from a merely similar title. Currently
  /// covers native connectors only, not the 13 site URLs in the catalogue.
  /// Background lookup progress per work (« Recherche sur 208 sites… »).
  final Map<String, SearchProgress> readerLookupProgress = {};
  final Map<String, int> _readerRevision = {};

  /// Changes whenever new readers were attached to [workId]; pages showing
  /// its chapters reload when it changes.
  int readerRevision(String workId) => _readerRevision[workId] ?? 0;

  /// Silent, remembered lookup: once per week for library works (date saved
  /// with the entry), once per day otherwise. No progress bar, no wait.
  /// A catalogue card (AniList metadata) becomes a readable work: it is
  /// matched by exact title/alias with the integrated connectors (MangaDex…)
  /// and with the library. Without a match, the work opens anyway and the
  /// engine searches every site for it (empty list = urgent lookup).
  Future<WorkInfo> resolveCatalogWork(WorkInfo meta) async {
    // Staff names and years are written differently from one database to
    // another: only titles and the comic family are compared here.
    final probe = WorkInfo(id: meta.id, title: meta.title, altTitles: meta.altTitles,
        type: meta.type);
    for (final e in entries) {
      if (sameWorkAcrossSources(e.work, probe)) return e.work;
    }
    final native = sources.all.where((s) =>
        s.id != _captures.id && s is! PublicCatalogSource).toList();
    final found = <WorkInfo>[];
    await Future.wait([
      for (final source in native)
        () async {
          for (final title in <String>{meta.title, ...meta.altTitles.take(2)}) {
            try {
              final results = await source.search(title, limit: 20)
                  .timeout(const Duration(seconds: 8));
              final hits = results.where((w) => sameWorkAcrossSources(probe, w)).toList();
              if (hits.isNotEmpty) {
                found.addAll(hits);
                return;
              }
            } catch (_) {
              return;
            }
          }
        }(),
    ]);
    if (found.isEmpty) return meta;
    final merged = mergeSearchResults(found);
    final best = merged.firstWhere((w) => sameWorkAcrossSources(w, probe), orElse: () => found.first);
    // Rich metadata from the catalogue fills the gaps of the connector record.
    return WorkInfo.fromJson({
      ...best.toJson(),
      if (best.description.isEmpty) 'description': meta.description,
      if (best.coverUrl == null) 'coverUrl': meta.coverUrl,
      'tags': {...meta.tags, ...best.tags}.toList(),
      'altTitles': {...best.altTitles, ...meta.altTitles, if (meta.title != best.title) meta.title}
          .take(16).toList(),
      'lastChapter': _maxChapter(best.lastChapter, meta.lastChapter),
    });
  }

  static String? _maxChapter(String? a, String? b) {
    final x = double.tryParse(a ?? '');
    final y = double.tryParse(b ?? '');
    if (x == null) return b ?? a;
    if (y == null) return a;
    return x >= y ? a : b;
  }

  /// The user pressed « Réessayer »: sources paused after errors (502/503/
  /// 504, time-outs) get a new chance immediately. HTTP 429 pauses stay.
  void resumePausedSources() => engine.breaker.resetAll();

  bool coverageRepairRunning = false;

  /// Library entries with an incomplete chapter list (from the chapter
  /// memory on disk) are completed with readers from every site.
  Future<int> repairLibraryCoverage({int max = 40}) async {
    if (coverageRepairRunning) return 0;
    coverageRepairRunning = true;
    var started = 0;
    try {
      for (final e in entries.toList()) {
        if (!_active || started >= max) break;
        if (e.work.type == ContentType.anime) continue;
        var chapters = _chapterCache[e.work.id];
        if (chapters == null) {
          final snapshot = await _readChapterSnapshot(e.work.id);
          if (snapshot == null) continue;
          // Same memory as opening the work: the trusted reference is ready.
          _chapterCache[e.work.id] = chapters = snapshot.$2;
          _chapterCachedAt[e.work.id] = snapshot.$1;
        }
        final latest = e.latestKnown.values.fold<double?>(null,
            (m, v) => m == null || v > m ? v : m);
        final announced = [e.work.lastChapter, latest?.floor().toString()]
            .whereType<String>()
            .fold<String?>(null, (m, v) =>
                m == null || (double.tryParse(v) ?? 0) > (double.tryParse(m) ?? 0) ? v : m);
        if (!Coverage.incomplete(chapters, lastChapter: announced)) continue;
        started++;
        AppLog.info('Chapitres incomplets pour ${e.work.title} : recherche d\'autres lecteurs');
        await _backgroundWebLookup(e.work, urgent: true);
      }
    } finally {
      coverageRepairRunning = false;
    }
    return started;
  }

  /// Titles used to find a work on a site: the main title, then every
  /// latin-script alternative title (« Disastrous Necromancer » for
  /// « Catastrophic Necromancer »), then the others. Up to 8.
  static List<String> _searchTitles(WorkInfo work) {
    bool latin(String t) => RegExp(r'^[\x00-\x7F\u00C0-\u024F\s\p{P}]+$', unicode: true).hasMatch(t);
    final alts = work.altTitles.where((t) => t.trim().length >= 3).toList();
    return <String>{
      work.title,
      ...alts.where(latin),
      ...alts.where((t) => !latin(t)),
    }.take(8).toList();
  }

  final Set<String> _lookupRunning = {};

  /// [urgent]: the chapter list is incomplete or every source failed; a new
  /// search is allowed every 12 h instead of once a week.
  Future<void> _backgroundWebLookup(WorkInfo work, {bool urgent = false}) async {
    if (work.type == ContentType.anime) return;
    if (_lookupRunning.contains(work.id)) return;
    final entry = _data.entries[work.id];
    // The 200+ sites are searched once, then the result is kept on disk:
    // again after 1 day when a language / sources are missing, otherwise
    // after 3 days (« Chercher d'autres sites » always searches at once).
    final at = _lookupDoneAt[work.id] ?? entry?.webLookupAt;
    final every = urgent ? const Duration(days: 1) : const Duration(days: 3);
    if (at != null && DateTime.now().difference(at) < every) return;
    _lookupRunning.add(work.id);
    try {
      // One or two works at a time (each asks ~150 sites): a library of
      // hundreds of imported works is searched little by little, never all
      // at once. The date is saved: a work is not searched again for days.
      await _lookupSlots.run(() async {
        await _breathe();
        await _runWebLookup(work, entry);
      });
    } finally {
      _lookupRunning.remove(work.id);
    }
  }

  final Slots _lookupSlots = Slots(DeviceProfile.light ? 1 : 2);

  Future<void> _runWebLookup(WorkInfo work, LibraryEntry? entry) async {
    if (entry != null) {
      entry.webLookupAt = DateTime.now();
      _changed();
    }
    // Wait for the trusted chapter list (API connectors): it is the
    // reference every web site must agree with before being attached.
    for (var i = 0; i < 40 && _chapterCache[work.id] == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    try {
      // Automatic searches are silent. A work outside the library only asks
      // the integrated connectors (MangaDex, SushiScan…): its sites come
      // from the catalogue index. Searching the ~150 sites whose catalogue
      // is unknown, one by one, happens for library works (in background)
      // or with « Chercher d'autres sites ».
      await locateNativeReaders(work, includeWebSites: entry != null);
    } catch (e) {
      AppLog.info('Recherche web des lecteurs ${work.title}: $e');
    }
  }

  Future<ReaderLookupReport> locateNativeReaders(WorkInfo work, {
    bool includeWebSites = true,
    bool includeNative = true,
    bool showProgress = false,
  }) async {
    final known = <String>{
      for (final link in [
        ...work.links,
        ...?_data.entries[work.id]?.work.links,
        ...?_locatedReaderLinks[work.id],
      ]) link.sourceId,
    };
    var checked = 0;
    var unavailable = 0;
    final found = <SourceLink>[];
    Future<void> inspect(ContentSource source) async {
      checked++;
      try {
        // Try the primary title, then up to three alternative names.
        // Only exact aliases are candidates; never fuzzy similarity.
        var matches = <WorkInfo>[];
        for (final title in _searchTitles(work)) {
          final results = await source.search(title, limit: 25)
              .timeout(const Duration(seconds: 12));
          matches = results.where((w) => sameWorkAcrossSources(work, w))
              .toList();
          if (matches.isNotEmpty) break;
        }
        if (matches.isEmpty) return;
        // Several cards (novel + comic, two editions…): each one is verified
        // and the most complete verified listing wins.
        final trusted = _referenceChapters(work.id);
        SourceLink? best;
        var bestCount = -1;
        for (final m in matches.take(3)) {
          final link = m.links.firstWhere(
            (l) => l.sourceId == source.id,
            orElse: () => SourceLink(sourceId: source.id, workId: ''),
          );
          if (link.workId.isEmpty) continue;
          // The work page itself must carry the same title: a search card can
          // be right while its link points elsewhere.
          if (source is PublicCatalogSource) {
            final page = await source.getWork(link.workId)
                .timeout(const Duration(seconds: 15));
            if (!titleConfirms(work, page.title)) {
              AppLog.info('Lecteur ${source.name} refusé pour ${work.title} : '
                  'la fiche s\'intitule « ${page.title} »');
              continue;
            }
          }
          final chapters = await source.listChapters(
            link.workId, langs: settings.comicLangs,
          ).timeout(const Duration(seconds: 25));
          final readable = chapters.where((c) => !c.isExternal).toList();
          if (readable.isEmpty) continue;
          // Never attach a site whose chapters contradict the trusted ones
          // (another series, a home page of "latest updates"…).
          // A connector reading one series by id is never « mixed ».
          final reason = ListingGuard.rejectReason(chapters, trusted,
              checkMixed: source is PublicCatalogSource);
          if (reason != null) {
            AppLog.info('Lecteur ${source.name} refusé pour ${work.title} : $reason');
            continue;
          }
          final count = readable.map((c) => c.key.id).toSet().length;
          if (count > bestCount) {
            best = link;
            bestCount = count;
          }
        }
        final link = best;
        if (link == null) return;
        found.add(link);
      } catch (e) {
        unavailable++;
        AppLog.info('Recherche de lecteur ${source.name}: $e');
      }
    }
    final candidates = <ContentSource>[
      if (includeNative)
        ...sources.all.where((s) => s.id != _captures.id &&
            s is! PublicCatalogSource && !known.contains(s.id) && !isSourceBlocked(s.id)),
      // A site whose whole catalogue is indexed does not have the work if
      // the index does not list it: no need to search it again.
      if (includeWebSites)
        ...webConnectors().where((s) => !known.contains(s.id) && !siteIndex.covers(s.id)),
    ];
    // Every site is queried, ten at a time; progress is published live.
    var cursor = 0;
    var done = 0;
    if (showProgress) {
      readerLookupProgress[work.id] = SearchProgress(total: candidates.length);
      notifyListeners();
    }
    Future<void> worker() async {
      while (cursor < candidates.length) {
        final before = found.length;
        await _breathe();
        await inspect(candidates[cursor++]);
        done++;
        // A site found is usable AT ONCE: the fiche reloads its chapters
        // without waiting for the 200 other sites.
        if (found.length > before) {
          final merged = <String, SourceLink>{
            for (final link in [...?_locatedReaderLinks[work.id], ...found])
              '${link.sourceId}:${link.workId}': link,
          };
          _locatedReaderLinks[work.id] = merged.values.toList();
          _chapterCache.remove(work.id);
          _chapterCachedAt.remove(work.id);
          _readerRevision[work.id] = readerRevision(work.id) + 1;
          notifyListeners();
        }
        if (!showProgress) continue;
        readerLookupProgress[work.id] = SearchProgress(total: candidates.length,
            done: done, failed: unavailable, found: found.length);
        if (done % 10 == 0 || done == candidates.length) notifyListeners();
      }
    }
    final workers = candidates.isEmpty ? 0 : candidates.length.clamp(1, 10).toInt();
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    readerLookupProgress.remove(work.id);
    if (includeWebSites) {
      _lookupDoneAt[work.id] = DateTime.now();
      if (found.isEmpty) unawaited(_saveLocatedReaders());
    }
    if (found.isNotEmpty) {
      final merged = <String, SourceLink>{
        for (final link in [...?_locatedReaderLinks[work.id], ...found])
          '${link.sourceId}:${link.workId}': link,
      };
      _locatedReaderLinks[work.id] = merged.values.toList();
      unawaited(_saveLocatedReaders());
      final entry = _data.entries[work.id];
      if (entry != null) {
        final preserved = <String, SourceLink>{
          for (final link in [...entry.work.links, ...found])
            '${link.sourceId}:${link.workId}': link,
        };
        entry.work = WorkInfo.fromJson({
          ...entry.work.toJson(),
          'links': preserved.values.map((l) => l.toJson()).toList(),
        });
        _changed();
      }
      _chapterCache.remove(work.id);
      _chapterCachedAt.remove(work.id);
      _readerRevision[work.id] = readerRevision(work.id) + 1;
    }
    notifyListeners();
    return ReaderLookupReport(
      checked: checked, found: found.length, unavailable: unavailable,
    );
  }

  /// « Ajouter un site » for one work: the address of the series page on
  /// ANY site (mgeko, asura, a French scan…). The site is found among the
  /// known ones (or added as a personal source), the page is read, and the
  /// link is kept for this work. Returns « site : N chapitres ».
  Future<String> linkSiteUrl(WorkInfo work, String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
      throw const SourceException('Adresse invalide : collez le lien complet (https://…).');
    }
    final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw const SourceException('C’est l’accueil du site : ouvrez la page de la série '
          '(…/manga/nom-de-la-serie/) et collez cette adresse.');
    }
    String bare(String h) => h.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final host = bare(uri.host);
    // SushiScan has its own connector (volumes).
    if (host == 'sushiscan.net') {
      final source = sources.byId('sushiscan_net');
      if (source is SushiScanSource) {
        final found = await source.seriesFromChapterUrl(uri.toString()).timeout(const Duration(seconds: 35));
        await linkNativeEdition(work, found.links.first);
        return 'SushiScan.net associé';
      }
    }
    CatalogSite? site;
    for (final c in [...catalogSites, ..._directorySites, for (final u in _userSources) u.toCatalogSite()]) {
      final h = Uri.tryParse(c.home)?.host;
      if (h != null && bare(h) == host) {
        site = c;
        break;
      }
    }
    site ??= await addPersonalSource(url: '${uri.scheme}://${uri.host}/');
    final connector = _publicConnectorFor(site);
    final seriesUrl = Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString();
    final List<SourceChapter> chapters;
    try {
      chapters = await connector.listChapters(seriesUrl, langs: settings.comicLangs)
          .timeout(const Duration(seconds: 40));
    } catch (e) {
      throw SourceException('${site.title} : page lue impossible ($e)');
    }
    final readable = chapters.where((c) => !c.isExternal).toList();
    if (readable.isEmpty) {
      throw SourceException('${site.title} : aucun chapitre trouvé sur cette page. '
          'Vérifiez que c’est bien la page de la série.');
    }
    final link = SourceLink(sourceId: connector.id, workId: seriesUrl);
    final entry = _data.entries[work.id] ?? addToLibrary(work);
    final merged = <String, SourceLink>{
      for (final item in [...entry.work.links, ...?_locatedReaderLinks[work.id], link])
        '${item.sourceId}:${item.workId}': item,
    };
    entry.work = WorkInfo.fromJson({
      ...entry.work.toJson(),
      'links': merged.values.map((item) => item.toJson()).toList(),
    });
    _locatedReaderLinks[work.id] = merged.values.toList();
    _chapterCache.remove(work.id);
    _chapterCachedAt.remove(work.id);
    _readerRevision[work.id] = readerRevision(work.id) + 1;
    unawaited(_saveLocatedReaders());
    _changed();
    double? top;
    for (final c in readable) {
      final n = c.key.number;
      if (n != null && (top == null || n > top)) top = n;
    }
    AppLog.info('Site ajouté à la main · ${work.title} : ${site.title}, ${readable.length} chapitres'
        '${top == null ? '' : ', dernier ${top == top.roundToDouble() ? top.toInt() : top}'}');
    return '${site.title} : ${readable.length} chapitres'
        '${top == null ? '' : ' (dernier : ch. ${top == top.roundToDouble() ? top.toInt() : top})'}';
  }

  /// Associate a user-selected edition from a direct Dart connector.
  /// Existing library, reading progress and locally cached pages are retained.
  Future<void> linkNativeEdition(WorkInfo work, SourceLink link) async {
    final source = sources.byId(link.sourceId);
    if (source == null || source is PublicCatalogSource ||
        source.id == _captures.id) {
      throw const SourceException('Ce connecteur n’est pas intégré à Pazulu.');
    }
    final remoteWork = await source.getWork(link.workId)
        .timeout(const Duration(seconds: 20));
    if (remoteWork.links.every((item) =>
        item.sourceId != link.sourceId || item.workId != link.workId)) {
      throw const SourceException('La fiche choisie n’est plus disponible.');
    }
    final entry = _data.entries[work.id] ?? addToLibrary(work);
    final merged = <String, SourceLink>{
      for (final item in [
        ...entry.work.links,
        ...?_locatedReaderLinks[work.id],
        link,
      ]) '${item.sourceId}:${item.workId}': item,
    };
    entry.work = WorkInfo.fromJson({
      ...entry.work.toJson(),
      'links': merged.values.map((item) => item.toJson()).toList(),
    });
    _locatedReaderLinks[work.id] = merged.values.toList();
    _nativeDiscoveryAt.remove(work.id);
    _chapterCache.remove(work.id);
    _chapterCachedAt.remove(work.id);
    _changed();
  }

  /// Planning: release dates published by the sources, per language.
  void _recordReleaseDates(LibraryEntry entry, List<SourceChapter> chapters) {
    final byLang = <String, List<DateTime>>{};
    final seen = <String>{};
    for (final c in chapters) {
      final d = c.publishedAt;
      if (d == null || !seen.add('${c.lang}|${c.key.id}')) continue;
      byLang.putIfAbsent(c.lang, () => []).add(d);
    }
    for (final pair in byLang.entries) {
      entry.releaseDates[pair.key] = ReleasePlanner.addDates(
          entry.releaseDates[pair.key] ?? const [], pair.value);
    }
  }

  void _recordRelease(LibraryEntry entry, String lang, DateTime when) {
    entry.releaseDates[lang] = ReleasePlanner.addDates(
        entry.releaseDates[lang] ?? const [], [when]);
  }

  /// Sorties confirmées récentes + prochaines sorties estimées (EN/FR).
  List<PlannedRelease> recentReleases({List<String>? langs}) => ReleasePlanner.recent(
      entries, updates, langs: langs ?? settings.comicLangs);

  /// Only series really in progress: paused, cancelled or finished works
  /// (status engine) never appear in the planning.
  List<PlannedRelease> releaseForecast({List<String>? langs}) => [
        for (final r in ReleasePlanner.forecast(
            entries.where((e) => seriesStatus(e.work).status.active),
            langs: langs ?? settings.comicLangs))
          if (r.state != ReleaseState.hiatus && r.state != ReleaseState.pauseLikely) r,
      ];

  // -------------------------------------------------------------------------
  // Animés (AniList : métadonnées, horaires, liens officiels)
  // -------------------------------------------------------------------------

  late final AniListClient anilist = AniListClient(engine.http);

  /// General weekly planning (all series, EN / FR / anime, many sources).
  late final ScheduleService schedule = ScheduleService(
    anilist: anilist,
    mangadex: _mangadex,
    http: engine.http,
    sites: webConnectors,
    entries: () => entries.where((e) => seriesStatus(e.work).status.active),
    animeReleases: animeReleases,
    supportDir: () => _supportDir,
    notify: notifyListeners,
  );
  final Map<int, AnimeInfo> animeInfos = {};

  /// Crunchyroll episode pages found in series pages (« id:épisode »).
  final Map<String, String> crEpisodeUrls = {};

  String? crunchyrollEpisodeUrl(AnimeInfo info, int? episode) =>
      (episode == null ? null : crEpisodeUrls['${info.id}:$episode']) ??
      Crunchyroll.urlFor(info, episode: episode);

  void rememberCrunchyrollEpisode(AnimeInfo info, int episode, String url) {
    crEpisodeUrls['${info.id}:$episode'] = url;
  }

  /// Crunchyroll numbering of a season when it keeps counting (Black Clover
  /// Season 2: +170, E171…). Learnt the first time an episode is found.
  final Map<int, int> crNumberOffsets = {};

  void rememberCrunchyrollNumber(AnimeInfo info, int episode, int crunchyrollNumber) {
    final offset = crunchyrollNumber - episode;
    if (offset < 0 || crNumberOffsets[info.id] == offset) return;
    crNumberOffsets[info.id] = offset;
    notifyListeners();
  }

  /// French weekly planning (release times in France), refreshed hourly.
  FrPlanning? frPlanning;
  Future<FrPlanning?>? _frLoading;

  Future<FrPlanning?> loadFrPlanning({bool force = false}) {
    final have = frPlanning;
    if (!force && have != null &&
        DateTime.now().difference(have.fetchedAt) < const Duration(hours: 1)) {
      return Future.value(have);
    }
    return _frLoading ??= () async {
      try {
        final fr = await FrPlanning.fetch(engine.http);
        frPlanning = fr;
        AppLog.info('Planning FR : ${fr.releases.length} sorties d\'animés lues');
        notifyListeners();
        return fr;
      } catch (e) {
        AppLog.info('Planning FR indisponible ($e) : heures AniList utilisées');
        return frPlanning;
      } finally {
        _frLoading = null;
      }
    }();
  }

  List<AnimeAiring> animeAirings = const [];
  DateTime? _animeAt;
  bool animeLoading = false;
  Object? animeError;

  List<LibraryEntry> get animeEntries =>
      [for (final e in entries) if (e.work.type == ContentType.anime) e];

  /// Refreshes the broadcast schedule of the anime in the library (exact
  /// times for 3 weeks, statuses, announced sequels). Cached 30 minutes.
  Future<void> refreshAnimePlanning({bool force = false}) async {
    if (animeLoading) return;
    final at = _animeAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return;
    }
    final ids = [
      for (final e in animeEntries)
        if (AniListClient.idOf(e.work) case final int id) id,
    ];
    if (ids.isEmpty) return;
    animeLoading = true;
    animeError = null;
    notifyListeners();
    try {
      final infos = await anilist.batch(ids);
      for (final info in infos) {
        animeInfos[info.id] = info;
      }
      final now = DateTime.now();
      animeAirings = await anilist.schedule(ids,
          now.subtract(const Duration(days: 21)), now.add(const Duration(days: 21)));
      _animeAt = DateTime.now();
    } catch (e) {
      animeError = e;
      AppLog.info('Planning des animés indisponible : $e');
    } finally {
      animeLoading = false;
      notifyListeners();
    }
  }

  List<PlannedRelease> animeReleases() =>
      ReleasePlanner.animePlanning(entries, animeInfos, animeAirings);

  LibraryEntry addAnime(AnimeInfo info, {TrackStatus status = TrackStatus.planned}) {
    animeInfos[info.id] = info;
    _animeAt = null; // the planning includes it at the next refresh
    return _data.entries[info.workId] ?? addToLibrary(info.toWork(), status: status);
  }

  void setEpisodesWatched(AnimeInfo info, int count) {
    final e = _data.entries[info.workId] ?? addAnime(info, status: TrackStatus.reading);
    final max = info.episodes ?? info.airedEpisodes;
    var value = count < 0 ? 0 : count;
    if (max != null && value > max) value = max;
    final delta = value - e.episodesWatched;
    e.episodesWatched = value;
    if (delta > 0 && delta <= 3) {
      _data.activity.addEpisodes(delta, minutesEach: info.duration ?? 24);
    }
    if (max != null && value >= max && info.status == 'FINISHED') {
      e.status = TrackStatus.completed;
    } else if (value > 0 && e.status == TrackStatus.planned) {
      e.status = TrackStatus.reading;
    }
    _changed();
    _checkAchievements();
  }

  // -------------------------------------------------------------------------
  // Niveaux, succès, statistiques
  // -------------------------------------------------------------------------

  ActivityLog get activity => _data.activity;

  ReaderStats get stats => ReaderStats.compute(entries, _data.activity);

  /// Achievements unlocked since the interface last showed them.
  final List<Achievement> pendingAchievements = [];

  void _logActivity({int chapters = 0}) {
    _data.activity.addChapters(chapters);
  }

  void _checkAchievements() {
    final fresh = Achievements.unlock(stats, _data.activity);
    if (fresh.isEmpty) return;
    pendingAchievements.addAll(fresh);
    _changed();
  }

  /// Called by the interface once the toast was shown.
  List<Achievement> takePendingAchievements() {
    final out = [...pendingAchievements];
    pendingAchievements.clear();
    return out;
  }

  /// Planning personnel de lecture d'une œuvre.
  void setReadingPlan(WorkInfo work, {required List<int> days, required int goal}) {
    final e = _data.entries[work.id] ?? addToLibrary(work, status: TrackStatus.reading);
    e.readingDays = (days.where((d) => d >= 1 && d <= 7).toSet().toList()..sort());
    e.readingGoal = goal.clamp(1, 50).toInt();
    _changed();
  }

  /// Every chapter already known for the work, whatever the source (all
  /// sources are peers): a newly found site must agree with them.
  List<SourceChapter> _referenceChapters(String workId) => [
    for (final c in _chapterCache[workId] ?? const <SourceChapter>[])
      if (!c.isExternal) c,
  ];

  static bool _outlier(SourceChapter c, List<SourceChapter> trusted) {
    final n = c.key.number;
    if (n == null) return false;
    double? max;
    var count = 0;
    for (final t in trusted) {
      final v = t.key.number;
      if (v == null) continue;
      count++;
      if (max == null || v > max) max = v;
    }
    if (max == null || count < 5) return false;
    return n > max * 1.3 + 15;
  }

  /// Removes wrongly attached web sources from a work: links, located
  /// readers, inflated "latest known" numbers and false notifications.
  void _detachSources(String workId, Set<String> sourceIds, {
    required Set<String> badKeys,
    required List<SourceChapter> clean,
  }) {
    final located = _locatedReaderLinks[workId];
    if (located != null) {
      _locatedReaderLinks[workId] =
          located.where((l) => !sourceIds.contains(l.sourceId)).toList();
      unawaited(_saveLocatedReaders());
    }
    final entry = _data.entries[workId];
    if (entry != null) {
      entry.work = WorkInfo.fromJson({
        ...entry.work.toJson(),
        'links': entry.work.links
            .where((l) => !sourceIds.contains(l.sourceId))
            .map((l) => l.toJson())
            .toList(),
      });
      // latestKnown may have been raised by the foreign chapters.
      for (final lang in entry.latestKnown.keys.toList()) {
        double? best;
        for (final c in clean) {
          final n = c.key.number;
          if (c.lang == lang && n != null && (best == null || n > best)) best = n;
        }
        if (best == null) {
          entry.latestKnown.remove(lang);
        } else if (entry.latestKnown[lang]! > best) {
          entry.latestKnown[lang] = best;
        }
      }
    }
    final cleanKeys = {for (final c in clean) c.key.id};
    if (entry != null) {
      final progress = entry.progress;
      progress.readKeys.removeWhere((k) => badKeys.contains(k) && !cleanKeys.contains(k));
      final last = progress.lastKey;
      if (last != null && badKeys.contains(last) && !cleanKeys.contains(last)) {
        // Resume at the furthest genuine chapter that was read.
        String? best;
        double bestN = -1;
        for (final k in progress.readKeys) {
          final n = double.tryParse(k);
          if (n != null && n > bestN) {
            bestN = n;
            best = k;
          }
        }
        progress.lastKey = best;
        progress.lastPage = 0;
      }
    }
    _data.updates.removeWhere((u) => u.workId == workId &&
        badKeys.contains(u.keyId) && !cleanKeys.contains(u.keyId));
    _readerRevision[workId] = readerRevision(workId) + 1;
    _changed();
  }

  void _rememberLatest(String workId, List<SourceChapter> chapters) {
    final entry = _data.entries[workId];
    if (entry == null) return;
    _recordReleaseDates(entry, chapters);
    var changed = false;
    final bySource = <String, List<SourceChapter>>{};
    for (final c in chapters) {
      bySource.putIfAbsent(c.sourceId, () => []).add(c);
      final n = c.key.number;
      if (n == null) continue;
      final known = entry.latestKnown[c.lang];
      if (known == null || n > known) {
        entry.latestKnown[c.lang] = n;
        changed = true;
      }
    }
    for (final pair in bySource.entries) {
      // Ajout à la bibliothèque après ouverture de la fiche : on fige la
      // référence de départ au lieu de notifier toute la série historique.
      ReleaseDetector.observe(entry, pair.key, pair.value,
          langs: settings.comicLangs);
    }
    if (changed) _changed();
  }

  // -------------------------------------------------------------------------
  // Bibliothèque
  // -------------------------------------------------------------------------

  LibraryEntry? entry(String workId) => _data.entries[workId];

  /// Une œuvre absente de MangaDex peut être suivie dans la bibliothèque.
  /// La fiche est locale (aucun faux connecteur, pas d'alertes automatiques).
  WorkInfo createManualWork(String title, ContentType type) {
    final cleaned = title.trim();
    if (cleaned.isEmpty) throw const FormatException('Le titre est obligatoire.');
    final id = 'manual:${DateTime.now().microsecondsSinceEpoch}';
    final work = WorkInfo(
      id: id,
      title: cleaned,
      type: type,
      languages: List<String>.from(settings.comicLangs),
    );
    _data.entries[id] = LibraryEntry(
      work: work, status: TrackStatus.planned, watch: false,
    );
    _changed();
    return work;
  }

  bool inLibrary(String workId) => _data.entries.containsKey(workId);

  // ---- Historique de lecture, doublons, pauses ----

  /// Chapitres ouverts, du plus récent au plus ancien (5 000 au plus).
  final List<HistoryItem> history = [];

  /// Paires de doublons que l'utilisateur a dit « pas la même œuvre ».
  final Set<String> ignoredDuplicates = {};

  /// Dernière fois que la proposition « mettre en pause » a été écartée.
  DateTime? pauseHintDismissedAt;

  Timer? _historySave;

  File? get _historyFile => _supportDir == null
      ? null
      : File('${_supportDir!.path}${Platform.pathSeparator}history.json');

  Future<void> _loadHistory() async {
    final f = _historyFile;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      history
        ..clear()
        ..addAll([for (final h in (raw['items'] as List? ?? const [])) HistoryItem.fromJson(h)]
            .whereType<HistoryItem>());
      ignoredDuplicates
        ..clear()
        ..addAll([for (final d in (raw['ignoredDuplicates'] as List? ?? const [])) '$d']);
      pauseHintDismissedAt = DateTime.tryParse('${raw['pauseHintDismissedAt']}');
    } catch (_) {
      // damaged: starts again
    }
  }

  void _saveHistorySoon() {
    _historySave?.cancel();
    _historySave = Timer(const Duration(seconds: 3), () async {
      final f = _historyFile;
      if (f == null) return;
      final json = {
        'items': [for (final h in history) h.toJson()],
        'ignoredDuplicates': ignoredDuplicates.toList(),
        if (pauseHintDismissedAt != null) 'pauseHintDismissedAt': pauseHintDismissedAt!.toIso8601String(),
      };
      try {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(json), flush: true);
        if (await f.exists()) await f.delete();
        await tmp.rename(f.path);
      } catch (e) {
        AppLog.info('Historique non enregistré : $e');
      }
    });
  }

  void _addHistory(WorkInfo work, String chapterId) {
    if (history.isNotEmpty && history.first.workId == work.id && history.first.chapterId == chapterId) return;
    history.insert(0, HistoryItem(workId: work.id, title: work.title, chapterId: chapterId, at: DateTime.now()));
    if (history.length > 5000) history.removeRange(5000, history.length);
    _saveHistorySoon();
  }

  void _markHistoryFinished(String workId, String chapterId) {
    for (final h in history.take(50)) {
      if (h.workId == workId && h.chapterId == chapterId) {
        h.finished = true;
        _saveHistorySoon();
        return;
      }
    }
    history.insert(0, HistoryItem(
        workId: workId, title: _data.entries[workId]?.work.title ?? '', chapterId: chapterId,
        at: DateTime.now(), finished: true));
    _saveHistorySoon();
  }

  void clearHistory() {
    history.clear();
    _saveHistorySoon();
    notifyListeners();
  }

  WorkStats statsFor(LibraryEntry e) {
    final latest = e.latestKnown.values.fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    return LibraryInsights.statsFor(e, history, latest: latest);
  }

  /// Lectures en cours pas ouvertes depuis 3 mois (proposition « en pause »,
  /// pas plus d'une fois par mois si elle a été écartée).
  List<LibraryEntry> get staleReadings {
    final d = pauseHintDismissedAt;
    if (d != null && DateTime.now().difference(d) < const Duration(days: 30)) return const [];
    return LibraryInsights.stale(entries);
  }

  void dismissPauseHint() {
    pauseHintDismissedAt = DateTime.now();
    _saveHistorySoon();
    notifyListeners();
  }

  void pauseAll(Iterable<LibraryEntry> list) {
    for (final e in list) {
      e.status = TrackStatus.paused;
      e.updatedAt = DateTime.now();
    }
    _changed();
  }

  /// Séries terminées (selon toutes les sources) où il reste des chapitres
  /// à lire, parmi les lectures en cours.
  List<LibraryEntry> get finishedWithChaptersLeft => [
        for (final e in entries)
          if (e.status == TrackStatus.reading &&
              seriesStatus(e.work).status == SeriesStatus.completed &&
              unreadCount(e) > 0)
            e,
      ];

  List<(LibraryEntry, LibraryEntry)> get duplicateEntries =>
      LibraryInsights.duplicates(entries, ignored: ignoredDuplicates);

  void ignoreDuplicate(LibraryEntry a, LibraryEntry b) {
    ignoredDuplicates.add(LibraryInsights.pairId(a.work.id, b.work.id));
    _saveHistorySoon();
    notifyListeners();
  }

  /// Fusionne deux fiches de la même œuvre : tout est gardé (chapitres lus,
  /// sites, favori, note, étiquettes), la position la plus avancée gagne.
  void mergeEntries(LibraryEntry keep, LibraryEntry drop) {
    if (identical(keep, drop)) return;
    final k = keep.progress, d = drop.progress;
    k.readKeys.addAll(d.readKeys);
    final kn = k.lastKey == null ? null : ChapterKey.parse(k.lastKey).number;
    final dn = d.lastKey == null ? null : ChapterKey.parse(d.lastKey).number;
    if (dn != null && (kn == null || dn > kn)) {
      k.lastKey = d.lastKey;
      k.lastPage = d.lastPage;
      k.lastLang = d.lastLang;
      k.lastGroup = d.lastGroup;
    }
    if (d.updatedAt != null && (k.updatedAt == null || d.updatedAt!.isAfter(k.updatedAt!))) {
      k.updatedAt = d.updatedAt;
    }
    final seen = <String>{};
    final links = [
      for (final l in [...keep.work.links, ...drop.work.links])
        if (seen.add('${l.sourceId}|${l.workId}')) l,
    ];
    keep.work = WorkInfo.fromJson({
      ...keep.work.toJson(),
      'links': [for (final l in links) l.toJson()],
      'altTitles': {...keep.work.altTitles, drop.work.title, ...drop.work.altTitles}
          .where((t) => t != keep.work.title).take(20).toList(),
      if (keep.work.coverUrl == null) 'coverUrl': drop.work.coverUrl,
    });
    keep.favorite = keep.favorite || drop.favorite;
    keep.watch = keep.watch || drop.watch;
    keep.rating ??= drop.rating;
    keep.tags = {...keep.tags, ...drop.tags}.toList();
    if (drop.note.isNotEmpty && !keep.note.contains(drop.note)) {
      keep.note = keep.note.isEmpty ? drop.note : '${keep.note}\n${drop.note}';
    }
    for (final e in drop.latestKnown.entries) {
      final v = keep.latestKnown[e.key];
      if (v == null || e.value > v) keep.latestKnown[e.key] = e.value;
    }
    if (keep.addedAt.isAfter(drop.addedAt)) keep.addedAt = drop.addedAt;
    for (var i = 0; i < history.length; i++) {
      final h = history[i];
      if (h.workId == drop.work.id) {
        history[i] = HistoryItem(workId: keep.work.id, title: keep.work.title,
            chapterId: h.chapterId, at: h.at, finished: h.finished);
      }
    }
    _saveHistorySoon();
    keep.updatedAt = DateTime.now();
    removeFromLibrary(drop.work.id);
    _changed();
  }

  // ---- Découverte : recommandations et disponibilité par langue ----

  List<WorkInfo>? _forYou;
  DateTime? _forYouAt;

  /// Pour qui ? « Parce que tu as aimé X » : titre de l'œuvre de la
  /// bibliothèque qui a amené chaque recommandation.
  final Map<String, String> becauseOf = {};

  /// Recommandations AniList à partir des œuvres préférées de la
  /// bibliothèque (favoris, mieux notées, plus lues) : celles conseillées
  /// par plusieurs d'entre elles d'abord ; déjà dans la bibliothèque
  /// exclues. Gardées 6 h.
  Future<List<WorkInfo>> recommendationsForYou({bool refresh = false}) async {
    final cached = _forYou;
    if (!refresh && cached != null && _forYouAt != null &&
        DateTime.now().difference(_forYouAt!) < const Duration(hours: 6)) {
      return cached;
    }
    int score(LibraryEntry e) =>
        (e.favorite ? 1000 : 0) + (e.rating ?? 0) * 50 + e.progress.readKeys.length;
    final seeds = [
      for (final e in entries)
        if (e.work.type != ContentType.anime && (e.favorite || e.rating != null || e.progress.readKeys.length >= 5)) e,
    ]..sort((a, b) => score(b).compareTo(score(a)));
    final votes = <String, (WorkInfo, int, int)>{}; // key → (work, votes, best rank)
    becauseOf.clear();
    for (final seed in seeds.take(6)) {
      List<WorkInfo> recs;
      try {
        recs = await anilist.recommendations(seed.work.title).timeout(const Duration(seconds: 15));
      } catch (_) {
        continue;
      }
      for (var i = 0; i < recs.length; i++) {
        final w = recs[i];
        final mine = entries.any((e) => sameWorkAcrossSources(e.work, w));
        if (mine) continue;
        final old = votes[w.id];
        votes[w.id] = (w, (old?.$2 ?? 0) + 1, old == null || i < old.$3 ? i : old.$3);
        becauseOf.putIfAbsent(w.id, () => seed.work.title);
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    final list = votes.values.toList()
      ..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
    _forYouAt = DateTime.now();
    return _forYou = [for (final v in list) v.$1];
  }

  final Map<String, bool> _availableCache = {};

  /// L'œuvre est listée par au moins un site de cette langue (d'après les
  /// catalogues des sites déjà lus ; rien n'est téléchargé ici).
  bool availableIn(WorkInfo w, String lang) {
    final key = '${w.id}|$lang|${siteIndex.titleCount}';
    final hit = _availableCache[key];
    if (hit != null) return hit;
    var ok = false;
    for (final l in siteIndex.linksFor([w.title, ...w.altTitles])) {
      final src = sources.byId(l.sourceId);
      if (src is PublicCatalogSource && src.site.languages.contains(lang)) {
        ok = true;
        break;
      }
    }
    if (_availableCache.length > 20000) _availableCache.clear();
    return _availableCache[key] = ok;
  }

  // ---- Défis, récap, connexion, rapport de bug, Windows ----

  List<MonthlyChallenge> get monthlyChallenges =>
      Recap.challenges(entries, _data.activity, history);

  YearRecap yearRecap(int year) => Recap.year(entries, _data.activity, history, year: year);

  /// false quand internet ne répond pas (vérifié au démarrage puis toutes
  /// les minutes, seulement quand Pazulu est au premier plan).
  final ValueNotifier<bool> online = ValueNotifier(true);
  Timer? _onlineTimer;

  void _startOnlineWatch() {
    _onlineTimer?.cancel();
    unawaited(checkOnline());
    _onlineTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_active) unawaited(checkOnline());
    });
  }

  Future<bool> checkOnline() async {
    var ok = false;
    for (final host in const ['github.com', 'graphql.anilist.co']) {
      try {
        final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
        if (r.isNotEmpty) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (online.value != ok) {
      online.value = ok;
      AppLog.info(ok ? 'Connexion retrouvée' : 'Hors ligne : seuls les chapitres téléchargés sont lisibles');
    }
    return ok;
  }

  /// Rapport de bug : un .zip dans Téléchargements avec le journal, la
  /// version, la machine et les réglages (sans la bibliothèque, sans
  /// historique ni données personnelles). Renvoie son chemin.
  Future<String> createBugReport() async {
    await AppLog.flush();
    final zip = ZipWriter();
    final logPath = AppLog.path;
    if (logPath != null) {
      final f = File(logPath);
      if (await f.exists()) zip.addBytes('pazulu.log', await f.readAsBytes());
    }
    zip.addText('infos.txt', [
      'Pazulu Reader $appVersion',
      'Date : ${DateTime.now().toIso8601String()}',
      'Système : ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Processeurs : ${Platform.numberOfProcessors} · mode ${DeviceProfile.mode} '
          '(${DeviceProfile.light ? 'léger' : 'complet'})',
      'Bibliothèque : ${entries.length} œuvres · ${history.length} passages d\'historique',
      'Index des sites : ${siteIndex.siteCount} sites · ${siteIndex.titleCount} titres',
      'Connexion : ${online.value ? 'en ligne' : 'hors ligne'}',
    ].join('\r\n'));
    final settingsJson = Map<String, dynamic>.from(settings.toJson())
      ..remove('blockedSources');
    zip.addText('reglages.json', const JsonEncoder.withIndent('  ').convert(settingsJson));
    final home = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    var dir = Directory('$home${Platform.pathSeparator}Downloads');
    if (!await dir.exists()) dir = Directory.systemTemp;
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 12);
    final out = File('${dir.path}${Platform.pathSeparator}pazulu-rapport-$stamp.zip');
    await out.writeAsBytes(zip.build(), flush: true);
    AppLog.info('Rapport de bug créé : ${out.path}');
    return out.path;
  }

  /// Démarrage avec Windows (clé « Run » de l'utilisateur, jamais pour
  /// toute la machine) : Pazulu s'ouvre réduit.
  Future<bool> setStartWithWindows(bool on) async {
    if (!Platform.isWindows) return false;
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      final r = on
          ? await Process.run('reg', ['add', key, '/v', 'Pazulu Reader', '/t', 'REG_SZ',
              '/d', '"${Platform.resolvedExecutable}" --minimized', '/f'])
          : await Process.run('reg', ['delete', key, '/v', 'Pazulu Reader', '/f']);
      final ok = r.exitCode == 0 || (!on && r.exitCode == 1);
      if (ok) updateSettings((s) => s.startWithWindows = on);
      return ok;
    } catch (e) {
      AppLog.info('Démarrage avec Windows non modifié : $e');
      return false;
    }
  }

  // ---- Résumés en français ----

  /// workId → (résumé FR, d'où il vient) ; « » = cherché, rien trouvé.
  final Map<String, (String, String)> _frSummaries = {};
  final Map<String, DateTime> _frTriedAt = {};
  final Map<String, Future<(String, String)?>> _frPending = {};
  Timer? _frSave;

  File? get _frFile => _supportDir == null
      ? null
      : File('${_supportDir!.path}${Platform.pathSeparator}resumes-fr.json');

  Future<void> _loadFrenchSummaries() async {
    final f = _frFile;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      final purged = <String>{};
      for (final e in (raw['found'] as Map? ?? const {}).entries) {
        final v = e.value;
        if (v is List && v.length == 2) {
          // Textes de site enregistrés par la 1.9.1 : effacés, l'œuvre est
          // recherchée à nouveau.
          final text = SiteBlurb.strip('${v[0]}', siteName: '${v[1]}');
          if (text.length < 60) {
            purged.add('${e.key}');
            continue;
          }
          if (SiteBlurb.looksCut(text)) {
            // Cut by the site: searched again for a complete one.
            purged.add('${e.key}');
            continue;
          }
          if (text != '${v[0]}') purged.add('');
          _frSummaries['${e.key}'] = (text, '${v[1]}');
        }
      }
      for (final e in (raw['tried'] as Map? ?? const {}).entries) {
        final d = DateTime.tryParse('${e.value}');
        if (d != null && !purged.contains('${e.key}') && raw['v'] == 3) _frTriedAt['${e.key}'] = d;
      }
      if (purged.isNotEmpty) _saveFrenchSummariesSoon();
    } catch (_) {}
  }

  void _saveFrenchSummariesSoon() {
    _frSave?.cancel();
    _frSave = Timer(const Duration(seconds: 2), () async {
      final f = _frFile;
      if (f == null) return;
      try {
        await f.writeAsString(jsonEncode({
          'v': 3,
          'found': {for (final e in _frSummaries.entries) e.key: [e.value.$1, e.value.$2]},
          'tried': {for (final e in _frTriedAt.entries) e.key: e.value.toIso8601String()},
        }));
      } catch (_) {}
    });
  }

  /// Résumé français déjà trouvé (sans rien chercher).
  (String, String)? cachedFrenchSummary(String workId) => _frSummaries[workId];

  /// Cherche un résumé en français pour [w] : d'abord sur les sites
  /// français qui ont l'œuvre (leur page de série, pas d'image), puis sur
  /// MangaDex. Gardé sur le disque ; une œuvre sans résumé FR n'est
  /// recherchée à nouveau qu'au bout de 7 jours. Aucun service de
  /// traduction : seulement des résumés écrits en français.
  Future<(String, String)?> frenchSummary(WorkInfo w) {
    if (!settings.frenchSummaries) return Future.value();
    if (w.description.isNotEmpty && FrenchText.looksFrench(w.description)) return Future.value();
    final hit = _frSummaries[w.id];
    if (hit != null) return Future.value(hit);
    final tried = _frTriedAt[w.id];
    if (tried != null && DateTime.now().difference(tried) < const Duration(days: 7)) return Future.value();
    return _frPending[w.id] ??= _findFrenchSummary(w).whenComplete(() => _frPending.remove(w.id));
  }

  Future<(String, String)?> _findFrenchSummary(WorkInfo w) async {
    (String, String)? found;
    (String, String)? cut;
    String clean(String t, [String? site]) => SiteBlurb.strip(t, siteName: site);
    bool good(String t) => t.trim().length >= 60 && FrenchText.looksFrench(t);
    // 1. Les sites français liés à l'œuvre (3 au plus).
    final frLinks = <SourceLink>[
      for (final l in {...w.links, ...siteIndex.linksFor([w.title, ...w.altTitles])})
        if (sources.byId(l.sourceId) case final PublicCatalogSource src
            when src.site.languages.contains('fr') && !isSourceBlocked(src.id))
          l,
    ];
    for (final l in frLinks.take(3)) {
      final src = sources.byId(l.sourceId)!;
      try {
        final page = await chapterGate.run(src.id, () => src.getWork(l.workId).timeout(const Duration(seconds: 15)),
            lane: 'fr');
        final text = clean(page.description, src.name);
        if (good(text)) {
          // A complete summary ends the search; a summary cut by the site
          // is kept aside in case nothing better is found.
          if (!SiteBlurb.looksCut(text)) {
            found = (text, src.name);
            break;
          }
          if (cut == null || text.length > cut.$1.length) cut = (text, src.name);
        }
      } catch (_) {}
    }
    // 2. MangaDex (résumés traduits par sa communauté).
    if (found == null) {
      try {
        final hits = await _mangadex.search(w.title, limit: 8).timeout(const Duration(seconds: 12));
        final match = sameMetadataWork(w.title, w.altTitles, hits);
        if (match != null) {
          var text = clean(match.description);
          if (!good(text)) text = clean((await _mangadex.getWork(match.id).timeout(const Duration(seconds: 12))).description);
          if (good(text)) found = (text, 'MangaDex');
        }
      } catch (_) {}
    }
    // Nothing complete: the longest cut summary, up to its last whole
    // sentence (« … » shows it was shortened by the site).
    if (found == null && cut != null) found = (SiteBlurb.keepWholeSentences(cut.$1), cut.$2);
    _frTriedAt[w.id] = DateTime.now();
    if (found != null) _frSummaries[w.id] = found;
    _saveFrenchSummariesSoon();
    return found;
  }

  // ---- Mes moments (pages marquées dans le lecteur) ----

  final List<Moment> moments = [];

  File? get _momentsFile => _supportDir == null
      ? null
      : File('${_supportDir!.path}${Platform.pathSeparator}moments.json');

  Future<void> _loadMoments() async {
    final f = _momentsFile;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is List) {
        moments
          ..clear()
          ..addAll(raw.map(Moment.fromJson).whereType<Moment>());
      }
    } catch (_) {
      // damaged file: kept aside, a new list starts
    }
  }

  Future<void> _saveMoments() async {
    final f = _momentsFile;
    if (f == null) return;
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final m in moments) m.toJson()]), flush: true);
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    } catch (e) {
      AppLog.info('Moments non enregistrés : $e');
    }
  }

  /// Marks (or unmarks if already there) a page as a moment.
  bool toggleMoment(WorkInfo work, ChapterKey key, int page) {
    final k = '${work.id}|${key.id}|$page';
    final i = moments.indexWhere((m) => m.key == k);
    final added = i < 0;
    if (added) {
      moments.insert(0, Moment(work: work, chapterId: key.id, chapterLabel: key.longLabel,
          page: page, at: DateTime.now()));
    } else {
      moments.removeAt(i);
    }
    unawaited(_saveMoments());
    notifyListeners();
    return added;
  }

  bool isMoment(String workId, String chapterId, int page) =>
      moments.any((m) => m.key == '$workId|$chapterId|$page');

  void removeMoment(Moment m) {
    moments.remove(m);
    unawaited(_saveMoments());
    notifyListeners();
  }

  void setMomentNote(Moment m, String note) {
    m.note = note.trim();
    unawaited(_saveMoments());
    notifyListeners();
  }

  bool _enriching = false;
  bool _aliasing = false;

  /// Autres titres d'une œuvre, d'après MangaUpdates (qui recense tous
  /// les noms : anglais, français, romanisé, noms des sites…). Une fiche
  /// importée sous un nom rare (« The Glutton Devourer Of Kings ») apprend
  /// qu'elle s'appelle aussi « The Second Coming of Gluttony » : les sites
  /// qui l'ont sous ce nom, l'image et le résumé sont retrouvés. Œuvres
  /// avec moins de 3 titres connus, une tentative par semaine, une requête
  /// toutes les 1,5 s au plus.
  Future<int> enrichAliases({int max = 120}) async {
    if (_aliasing) return 0;
    _aliasing = true;
    var done = 0;
    try {
      final todo = [
        for (final e in entries)
          if (e.work.type != ContentType.anime && e.work.altTitles.length < 3 &&
              (_metaTriedAt['mu:${e.work.id}'] == null ||
                  DateTime.now().difference(_metaTriedAt['mu:${e.work.id}']!) > const Duration(days: 7)))
            e,
      ].take(max).toList();
      for (final e in todo) {
        if (_disposed) break;
        await _breathe();
        final titles = [cleanImportedTitle(e.work.title), ...e.work.altTitles];
        try {
          final id = await mangaUpdates.findSeries(titles).timeout(const Duration(seconds: 15));
          _metaTriedAt['mu:${e.work.id}'] = DateTime.now();
          if (id == null) continue;
          final names = await mangaUpdates.names(id).timeout(const Duration(seconds: 15));
          final known = {for (final t in titles) SiteTitleIndex.norm(t)};
          final added = [
            for (final n in names)
              if (n.length >= 3 && n.length <= 120 && known.add(SiteTitleIndex.norm(n))) n,
          ];
          if (added.isEmpty) continue;
          e.work = WorkInfo.fromJson({
            ...e.work.toJson(),
            'altTitles': [...e.work.altTitles, ...added].take(24).toList(),
          });
          // New names: sites, cover and summary are looked for again.
          e.webLookupAt = null;
          _lookupDoneAt.remove(e.work.id);
          _metaTriedAt.remove(_metaKey(e));
          _frTriedAt.remove(e.work.id);
          done++;
          _changed();
        } catch (err) {
          AppLog.info('Autres titres non trouvés pour ${e.work.title} : $err');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      if (done > 0) {
        AppLog.info('Autres titres ajoutés (MangaUpdates) : $done œuvre(s)');
        unawaited(_saveLocatedReaders());
        // Covers of the works that now have more names.
        unawaited(enrichLibraryMetadata());
        unawaited(repairLibraryCoverage());
      }
    } finally {
      _aliasing = false;
    }
    return done;
  }

  /// Cover addresses that did not load (reported by the screen).
  final Set<String> _brokenCovers = {};
  Timer? _brokenTimer;

  /// A library cover does not load: the work's cover is looked for on
  /// AniList / MangaDex a few seconds later (several reports, one pass).
  void coverFailed(String url) {
    if (!_brokenCovers.add(url)) return;
    if (!entries.any((e) => e.work.coverUrl == url)) return;
    if (_enriching) {
      _enrichAgain = true;
      return;
    }
    _brokenTimer?.cancel();
    _brokenTimer = Timer(const Duration(seconds: 3), () => unawaited(enrichLibraryMetadata()));
  }

  bool _enrichAgain = false;

  bool _needsCover(LibraryEntry e) {
    final c = e.work.coverUrl;
    return c == null || c.isEmpty || _brokenCovers.contains(c);
  }

  /// Library works without a cover (imported from bookmarks, created by
  /// hand…) are compared with the AniList catalogue: when the same work is
  /// found (same title or alias), its cover address, summary, genres,
  /// status, authors and other titles are added. The work keeps its id,
  /// its sites and its progress. Metadata only: the cover is shown like
  /// any other library cover. Each work is tried once a week.
  Future<int> enrichLibraryMetadata({int max = 400}) async {
    if (_enriching) return 0;
    _enriching = true;
    var done = 0;
    try {
      final todo = [
        for (final e in entries)
          if (e.work.type != ContentType.anime && _needsCover(e) &&
              (_metaTriedAt[_metaKey(e)] == null ||
                  DateTime.now().difference(_metaTriedAt[_metaKey(e)]!) > const Duration(days: 7)))
            e,
      ].take(max).toList();
      for (final e in todo) {
        if (_disposed) break;
        await _breathe();
        final clean = cleanImportedTitle(e.work.title);
        try {
          // A title cut by the browser (« The Reincarnated Assassin Is a
          // Geni… ») is searched by its beginning.
          final truncated = RegExp(r'(\.\.\.|…)\s*$').hasMatch(e.work.title);
          final hits = await anilist.comicCatalog(search: clean, perPage: 8, sort: 'SEARCH_MATCH')
              .timeout(const Duration(seconds: 15));
          // Answer received: not asked again before a week (kept on disk).
          _metaTriedAt[_metaKey(e)] = DateTime.now();
          var match = sameMetadataWork(clean, e.work.altTitles, hits, truncated: truncated);
          // Not on AniList (or without a cover there): MangaDex, which
          // lists many webtoons AniList does not have.
          if (match == null || match.coverUrl == null) {
            try {
              final md = await _mangadex.search(clean, limit: 10).timeout(const Duration(seconds: 12));
              final other = sameMetadataWork(clean, e.work.altTitles, md, truncated: truncated);
              if (other != null && other.coverUrl != null) {
                match = match == null
                    ? other
                    : WorkInfo.fromJson({...match.toJson(), 'coverUrl': other.coverUrl});
              }
            } catch (_) {
              // MangaDex busy: next pass.
            }
          }
          if (match == null) {
            if (clean != e.work.title) {
              e.work = WorkInfo.fromJson({...e.work.toJson(), 'title': clean});
              _changed();
            }
            continue;
          }
          final old = e.work;
          e.work = WorkInfo.fromJson({
            ...old.toJson(),
            'title': clean,
            'coverUrl': match.coverUrl ?? old.coverUrl,
            if (old.description.isEmpty) 'description': match.description,
            'type': (old.type == ContentType.other ? match.type : old.type).name,
            'publicationStatus': old.publicationStatus ?? match.publicationStatus,
            'tags': {...old.tags, ...match.tags}.toList(),
            'year': old.year ?? match.year,
            'authors': old.authors.isEmpty ? match.authors : old.authors,
            'altTitles': {...old.altTitles, if (match.title != clean) match.title, ...match.altTitles}
                .where((t) => t != clean).take(16).toList(),
            'lastChapter': _maxChapter(old.lastChapter, match.lastChapter),
          });
          if (match.publicationStatus != null) {
            _recordStatusVote(e.work.id, 'AniList', match.publicationStatus!);
          }
          done++;
          _changed();
        } catch (err) {
          AppLog.info('Fiche AniList non trouvée pour ${e.work.title} : $err');
        }
        // AniList allows ~60 requests a minute.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
      if (done > 0) AppLog.info('Fiches complétées (image, résumé, genres) : $done');
      unawaited(_saveLocatedReaders());
    } finally {
      _enriching = false;
      if (_enrichAgain && !_disposed) {
        _enrichAgain = false;
        _brokenTimer = Timer(const Duration(seconds: 3), () => unawaited(enrichLibraryMetadata()));
      }
    }
    return done;
  }

  /// The catalogue entry that is the same work: same title or alias (also
  /// written a little differently), or — for a title cut by the browser —
  /// one title starting with the known beginning.
  static WorkInfo? sameMetadataWork(String title, List<String> alt, List<WorkInfo> hits,
      {bool truncated = false}) {
    final mine = {
      for (final t in [title, ...alt]) SiteTitleIndex.loose(SiteTitleIndex.norm(t)),
    }..removeWhere((t) => t.length < 3);
    Iterable<String> theirs(WorkInfo w) =>
        [w.title, ...w.altTitles].map((t) => SiteTitleIndex.loose(SiteTitleIndex.norm(t)));
    for (final w in hits) {
      if (theirs(w).any(mine.contains)) return w;
    }
    if (truncated) {
      final start = SiteTitleIndex.loose(SiteTitleIndex.norm(title));
      if (start.length >= 12) {
        for (final w in hits) {
          if (theirs(w).any((t) => t.startsWith(start))) return w;
        }
      }
    }
    return null;
  }

  final Map<String, DateTime> _metaTriedAt = {};

  /// One try per cover address (a new broken address is tried again; the
  /// « v2 » ignores the tries of 1.2/1.3 made without MangaDex).
  String _metaKey(LibraryEntry e) => 'v2:${e.work.id}:${e.work.coverUrl ?? ''}';

  /// Imports the readings found in a browser bookmarks export (HTML file
  /// chosen by the user): each series is added to the library with every
  /// site that has it, and the chapter of the bookmark becomes the reading
  /// position (earlier chapters marked as read). An existing reading is
  /// never moved backwards. Nothing is downloaded here.
  Future<BookmarkImportReport> importBookmarks(String html) async {
    await _indexLoading;
    final marks = parseBookmarksHtml(html);
    final hostToSource = <String, String>{};
    for (final site in activeSources) {
      if (site.hasReaderConnector) continue;
      try {
        hostToSource.putIfAbsent(_normalizedHost(site.home), () => _publicConnectorFor(site).id);
      } catch (_) {}
    }
    final readings = findReadings(
      marks,
      sourceForHost: (h) => hostToSource[h],
      titlesOf: (id) => siteIndex.bySource[id] ?? const <IndexedTitle>[],
      titleKnown: (t) => siteIndex.linksFor([t]).isNotEmpty,
    );
    var added = 0, updated = 0, positioned = 0;
    for (final r in readings) {
      final seen = <String>{};
      final links = <SourceLink>[
        if (r.sourceId != null && r.seriesUrl != null)
          SourceLink(sourceId: r.sourceId!, workId: r.seriesUrl!),
        ...siteIndex.linksFor([r.title]),
      ].where((l) => seen.add(l.sourceId)).toList();
      final probe = WorkInfo(id: 'index:${r.key}', title: r.title, links: links);
      LibraryEntry? entry;
      for (final e in entries) {
        if (sameWorkAcrossSources(e.work, probe)) {
          entry = e;
          break;
        }
      }
      if (entry == null) {
        entry = LibraryEntry(work: probe, status: TrackStatus.reading);
        _data.entries[probe.id] = entry;
        added++;
      } else {
        updated++;
      }
      final n = r.chapter;
      if (n == null || n <= 0) continue;
      final p = entry.progress;
      final current = p.lastKey == null ? null : ChapterKey.parse(p.lastKey).number;
      if (current != null && current >= n) continue;
      final whole = n.floor();
      for (var i = 1; i < whole && i <= 3000; i++) {
        p.readKeys.add(ChapterKey.parse('$i').id);
      }
      final label = n == whole ? '$whole' : '$n';
      p.lastKey = ChapterKey.parse(label).id;
      p.lastPage = 0;
      p.updatedAt = DateTime.now();
      if (entry.status == TrackStatus.planned || entry.status == TrackStatus.discover) {
        entry.status = TrackStatus.reading;
      }
      entry.updatedAt = DateTime.now();
      positioned++;
    }
    if (readings.isNotEmpty) {
      _changed();
      // Cover, summary, genres, status: compared with the AniList catalogue
      // right away, the library fills in as the answers arrive.
      unawaited(enrichAliases().then((_) => enrichLibraryMetadata()));
    }
    AppLog.info('Import des favoris : ${marks.length} liens, ${readings.length} lectures, '
        '$added ajoutées, $updated déjà présentes, $positioned positions de lecture.');
    return BookmarkImportReport(
        links: marks.length, readings: readings.length, added: added, updated: updated,
        positioned: positioned);
  }

  LibraryEntry addToLibrary(WorkInfo work, {TrackStatus status = TrackStatus.planned}) {
    final existing = _data.entries[work.id];
    if (existing != null) return existing;
    final e = LibraryEntry(work: work, status: status);
    _data.entries[work.id] = e;
    final cached = _chapterCache[work.id];
    if (cached != null) _rememberLatest(work.id, cached);
    _changed();
    return e;
  }

  void removeFromLibrary(String workId) {
    if (_data.entries.remove(workId) != null) {
      _data.updates.removeWhere((u) => u.workId == workId);
      _changed();
    }
  }

  /// Removes a work and returns what is needed to put it back exactly as
  /// it was (progress, notifications) — « Annuler » after a wrong click.
  (LibraryEntry, List<UpdateItem>)? removeWithUndo(String workId) {
    final e = _data.entries.remove(workId);
    if (e == null) return null;
    final updates = [for (final u in _data.updates) if (u.workId == workId) u];
    _data.updates.removeWhere((u) => u.workId == workId);
    _changed();
    return (e, updates);
  }

  void restoreEntry((LibraryEntry, List<UpdateItem>) removed) {
    final (e, updates) = removed;
    _data.entries[e.work.id] = e;
    _data.updates.addAll(updates);
    _changed();
  }

  /// Chapters known but not read yet (from the numbers).
  int unreadCount(LibraryEntry e) => ReleasePlanner.unreadEstimate(e, settings.comicLangs);

  /// First launch: which language is read first everywhere.
  void chooseLanguagePriority(String first) {
    updateSettings((s) {
      final other = first == 'fr' ? 'en' : 'fr';
      s.comicLangs = [first, other, ...s.comicLangs.where((l) => l != first && l != other)];
      s.langChosen = true;
    });
    AppLog.info('Langue prioritaire choisie : ${first.toUpperCase()}');
  }

  // ------------------------------------------------------------ app updates

  final AppUpdater _updater = AppUpdater();
  Timer? _updateTimer;

  /// Newer version found on GitHub (null = up to date / not checked).
  AppUpdateInfo? availableUpdate;
  DateTime? updateCheckedAt;
  String? updateError;
  bool checkingUpdate = false;

  /// 0..1 while the update downloads, null otherwise.
  double? updateProgress;

  String get updateRepo {
    final own = _data.settings.updateRepo.trim();
    return own.isNotEmpty ? own : defaultUpdateRepo;
  }

  bool get updatesConfigured => AppUpdater.validRepo(updateRepo);

  void _scheduleUpdateChecks() {
    _updateTimer?.cancel();
    if (!_data.settings.autoUpdateCheck) return;
    Timer(const Duration(seconds: 8), () => unawaited(checkForAppUpdate()));
    _updateTimer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(checkForAppUpdate()));
  }

  void setUpdateSettings({String? repo, bool? auto}) {
    final st = _data.settings;
    if (repo != null) st.updateRepo = repo.trim();
    if (auto != null) st.autoUpdateCheck = auto;
    _changed();
    _scheduleUpdateChecks();
  }

  Future<void> checkForAppUpdate() async {
    if (checkingUpdate || !updatesConfigured) return;
    checkingUpdate = true;
    updateError = null;
    notifyListeners();
    try {
      availableUpdate = await _updater.check(updateRepo, appVersion);
      updateCheckedAt = DateTime.now();
      if (availableUpdate != null) {
        AppLog.info('Mise à jour disponible : ${availableUpdate!.version} (installée : $appVersion)');
      }
    } catch (e) {
      updateError = '$e';
      AppLog.info('Vérification de mise à jour impossible : $e');
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  /// The « Mise à jour » button: one press is enough. Looks on GitHub if
  /// needed, then downloads and installs the newer version at once
  /// (Pazulu restarts by itself). Nothing happens when already up to date.
  Future<void> updateNow() async {
    if (updateProgress != null) return;
    // The last attempt failed (Pazulu restarted in the old version): no new
    // download on its own, the « Réessayer » button stays available.
    if (updateFailedVersion != null) {
      if (availableUpdate == null) await checkForAppUpdate();
      return;
    }
    if (availableUpdate == null) {
      await checkForAppUpdate();
    }
    if (availableUpdate != null) await installAppUpdate();
  }

  /// Version whose install failed at the last restart (shown with the
  /// error; one press on « Réessayer » tries again).
  String? updateFailedVersion;

  Future<void> _checkFailedInstall() async {
    final failed = await AppUpdater.failedInstall(appVersion);
    if (failed == null) return;
    updateFailedVersion = failed.$1;
    updateError = 'La mise à jour vers ${failed.$1} ne s\'est pas installée. '
        'Réessaie, ou installe PazuluReader-${failed.$1}-setup.exe depuis GitHub.';
    AppLog.info('Mise à jour ${failed.$1} non installée.\n${failed.$2}');
    notifyListeners();
  }

  /// Downloads the new version, saves everything, starts the installer and
  /// quits: Pazulu restarts by itself in the new version.
  Future<void> installAppUpdate() async {
    final info = availableUpdate;
    if (info == null || updateProgress != null) return;
    updateProgress = 0;
    updateError = null;
    updateFailedVersion = null;
    notifyListeners();
    var lastNotify = DateTime(2000);
    final useSetup = AppUpdater.installedWithSetup() && info.setupUrl != null;
    try {
      final zip = await _updater.download(info, useSetup: useSetup, onProgress: (v) {
        updateProgress = v;
        final now = DateTime.now();
        if (now.difference(lastNotify) > const Duration(milliseconds: 150)) {
          lastNotify = now;
          notifyListeners();
        }
      });
      updateProgress = 1;
      notifyListeners();
      AppLog.info('Mise à jour ${info.version} téléchargée, installation…');
      await flush();
      await AppUpdater.markPending(info.version);
      if (useSetup) {
        await _updater.launchSetup(zip);
      } else {
        await _updater.launchInstaller(zip);
      }
      exit(0);
    } catch (e) {
      updateProgress = null;
      updateError = '$e';
      AppLog.info('Mise à jour impossible : $e');
      notifyListeners();
    }
  }

  /// Accent et mode clair / sombre, appliqués à l'instant (sans recharger
  /// les listes de chapitres comme le ferait updateSettings).
  void setAppearance({String? accent, bool? dark}) {
    final st = _data.settings;
    if (accent != null) st.themeId = accent;
    if (dark != null) st.darkMode = dark;
    _changed();
  }

  void toggleDarkMode() => setAppearance(dark: !_data.settings.darkMode);

  void addRecentSearch(String query) {
    final q = query.trim();
    if (q.length < 2) return;
    // Not through updateSettings: that one reloads the chapter lists.
    final st = _data.settings;
    st.recentSearches = [q, ...st.recentSearches.where((x) => x.toLowerCase() != q.toLowerCase())]
        .take(12).toList();
    _changed();
  }

  void clearRecentSearches() {
    _data.settings.recentSearches = [];
    _changed();
  }

  void updateEntry(String workId, void Function(LibraryEntry e) change) {
    final e = _data.entries[workId];
    if (e == null) return;
    change(e);
    e.updatedAt = DateTime.now();
    _changed();
  }

  /// Œuvres en cours, de la plus récemment lue à la plus ancienne.
  List<LibraryEntry> continueReading() {
    final list = entries
        .where((e) => e.progress.updatedAt != null && e.status != TrackStatus.dropped)
        .toList()
      ..sort((a, b) => b.progress.updatedAt!.compareTo(a.progress.updatedAt!));
    return list.take(20).toList();
  }

  /// Enregistre la position de lecture (ajoute l'œuvre si besoin).
  void recordProgress({
    required WorkInfo work,
    required ChapterKey key,
    required int page,
    required int pageCount,
    required SourceChapter variant,
  }) {
    final e = _data.entries[work.id] ?? addToLibrary(work, status: TrackStatus.reading);
    final p = e.progress;
    if (p.lastKey != key.id) _addHistory(work, key.id);
    p.lastKey = key.id;
    p.lastPage = page;
    p.lastLang = variant.lang;
    p.lastGroup = variant.group;
    p.updatedAt = DateTime.now();
    if (pageCount > 0 && page >= pageCount - 1 && p.readKeys.add(key.id)) {
      _markHistoryFinished(work.id, key.id);
      _logActivity(chapters: 1);
      _checkAchievements();
    }
    if (e.status == TrackStatus.planned || e.status == TrackStatus.discover) {
      e.status = TrackStatus.reading;
    }
    e.updatedAt = DateTime.now();
    _changed();
  }

  void setRead(WorkInfo work, Iterable<ChapterKey> keys, bool read) {
    final e = _data.entries[work.id] ?? addToLibrary(work, status: TrackStatus.reading);
    var added = 0;
    for (final k in keys) {
      if (read) {
        if (e.progress.readKeys.add(k.id)) added++;
      } else {
        e.progress.readKeys.remove(k.id);
      }
    }
    // « Mark everything before as read » is catching up the past, not
    // today's reading: only a few chapters at once count in the journal.
    if (added > 0 && added <= 3) _logActivity(chapters: added);
    e.updatedAt = DateTime.now();
    _changed();
    _checkAchievements();
  }

  /// Reading language of a work (null = automatic, in the order of the
  /// settings). Any reader of that language may be used.
  void setPreferredLang(WorkInfo work, String? lang) {
    // Works outside the library keep the choice for this session.
    if (lang == null) {
      _sessionLang.remove(work.id);
    } else {
      _sessionLang[work.id] = lang;
    }
    final e = _data.entries[work.id];
    if (e == null) {
      notifyListeners();
      return;
    }
    e.preferredLang = lang;
    e.preferredGroup = null;
    e.preferredSourceId = null;
    e.updatedAt = DateTime.now();
    _changed();
  }

  final Map<String, String> _sessionLang = {};
  final Set<String> _consensusLogged = {};
  final Map<String, Set<String>> _unconfirmedAhead = {};

  /// workId → « lang|chapter » → first time the app saw it (kept on disk).
  final Map<String, Map<String, String>> _firstSeen = {};

  /// Release date of a chapter when no site writes one next to it, from the
  /// most to the least precise: the earliest time any site's « latest
  /// updates » (or MangaDex) showed it — the site that released it first —,
  /// a new-chapter notification, then the first time the app saw it.
  /// Returns (date, label prefix) or null.
  (DateTime, String)? fallbackReleaseDate(WorkInfo work, ChapterGroup g) {
    final titles = [work.title, ...work.altTitles];
    final feed = schedule.chapterReleaseDate(titles, g.key.id);
    if (feed != null) return (feed, 'Sorti');
    DateTime? best;
    for (final u in _data.updates) {
      if (u.workId != work.id || u.keyId != g.key.id) continue;
      final d = u.publishedAt ?? u.foundAt;
      if (best == null || d.isBefore(best)) best = d;
    }
    if (best != null) return (best, 'Repéré');
    final seen = _firstSeen[work.id];
    if (seen != null) {
      for (final v in g.variants) {
        final d = DateTime.tryParse(seen['${v.lang}|${g.key.id}'] ?? '');
        if (d != null && (best == null || d.isBefore(best))) best = d;
      }
    }
    return best == null ? null : (best, 'Repéré');
  }

  /// Chapter announced by one site only, ahead of the others (see
  /// [ChapterConsensus.unconfirmedAhead]).
  bool isAheadUnconfirmed(String workId, String lang, String keyId) =>
      _unconfirmedAhead[workId]?.contains('$lang|$keyId') ?? false;

  /// Reading language chosen for a work (library or not), null = automatic.
  String? preferredLangOf(String workId) =>
      _data.entries[workId]?.preferredLang ?? _sessionLang[workId];

  void setPreferredVariant(WorkInfo work, SourceChapter v, {bool explicit = false}) {
    final e = _data.entries[work.id] ?? addToLibrary(work, status: TrackStatus.reading);
    // The reading language only changes with « Lire en », « Garder ce
    // lecteur » or the language switch (explicit), or when none was chosen:
    // opening ONE chapter in English because the French one was missing
    // must not switch the whole work to English.
    if (explicit) {
      e.preferredLang = v.lang;
      _sessionLang[work.id] = v.lang;
    }
    e.preferredLang ??= v.lang;
    if (e.preferredLang != v.lang) {
      e.updatedAt = DateTime.now();
      _changed();
      return;
    }
    e.preferredGroup = v.group;
    e.preferredSourceId = v.sourceId;
    e.updatedAt = DateTime.now();
    _changed();
  }

  // -------------------------------------------------------------------------
  // Nouveautés
  // -------------------------------------------------------------------------

  /// Verify actual chapter feeds (native + user-linked public listings).
  /// The report is rebuilt on each check so "checked" never counts a source
  /// that was unavailable, unlinked or skipped. Current unread availability is
  /// shown on the FIRST check; only publication deltas create notifications.
  Future<int> checkUpdates({bool forceSiteScan = false}) async {
    if (checking) return 0;
    checking = true;
    lastCheckError = null;
    lastListingError = null;
    listingChecks = 0;
    listingFailures = 0;
    _feedCheckResults.clear();
    notifyListeners();
    var found = 0;
    var nativeFailures = 0;
    final known = _data.updates.map((u) => u.id).toSet();
    // Anime follow AniList broadcast schedules (refreshAnimePlanning).
    final watched = entries.where((e) => e.watch && e.work.type != ContentType.anime).toList();
    final languages = settings.comicLangs.toSet().toList();
    try {
      for (final e in watched) {
        if (!_active) break;
        await _breathe();
        for (final link in e.work.links) {
          final source = sources.byId(link.sourceId);
          if (source == null || isSourceBlocked(link.sourceId)) continue;
          try {
            // Same traffic control as the chapter engines (2 requests max
            // per site, French / English teams).
            final latest = await chapterGate.run(source.id, () => source.latestChapters(
              link.workId, langs: languages, limit: 80,
            ).timeout(const Duration(seconds: 30)), lane: _laneOf(source));
            final now = DateTime.now();
            final published = latest.where((c) => c.publishedAt == null ||
                !c.publishedAt!.isAfter(now)).toList();
            _recordReleaseDates(e, published);
            for (final lang in languages) {
              final langChapters = published.where((c) => c.lang == lang).toList();
              final availability = ReadAvailability.calculate(e.progress, langChapters);
              _feedCheckResults.add(FeedCheckResult(
                workId: e.work.id, workTitle: e.work.title,
                sourceId: source.id, sourceName: source.name, language: lang,
                state: FeedCheckState.checked, checkedAt: now,
                chapterCount: availability.total,
                unreadCount: availability.unread,
                unreadKeys: availability.unreadKeys,
                latestChapter: availability.latest,
                nextUnread: availability.nextUnread,
                nextUrl: availability.nextUrl,
                detail: availability.total == 0
                    ? 'Aucun chapitre public dans cette langue.'
                    : 'Flux public confirmé (derniers chapitres).',
              ));
            }
            final fresh = ReleaseDetector.observe(
              e, source.id, published, langs: languages,
            );
            for (final c in fresh) {
              // A FR chapter only one site has, ahead of every other FR
              // source while the EN one exists: not announced (« FR ? »).
              if (LanguageConsensus.aheadOfPeers(e, source.id, c.lang, c.key.id) ||
                  LanguageConsensus.singleSourceAhead(e, source.id, c.lang, c.key.id)) {
                AppLog.info('Sortie ${c.lang.toUpperCase()} non confirmée ignorée : '
                    '${e.work.title} ${c.key.longLabel} (${source.name} seul)');
                continue;
              }
              final item = UpdateItem(
                workId: e.work.id, title: e.work.title,
                coverUrl: e.work.coverUrl,
                keyId: c.key.id, lang: c.lang, group: c.group,
                foundAt: now, publishedAt: c.publishedAt,
              );
              if (known.add(item.id)) {
                _data.updates.insert(0, item);
                found++;
                if (c.publishedAt == null) _recordRelease(e, c.lang, now);
              }
            }
          } catch (err, st) {
            nativeFailures++;
            AppLog.error('Verification de ${e.work.title} via ${source.name}', err, st);
            lastCheckError = err.toString();
            for (final lang in languages) {
              _feedCheckResults.add(FeedCheckResult(
                workId: e.work.id, workTitle: e.work.title,
                sourceId: source.id, sourceName: source.name, language: lang,
                state: FeedCheckState.failed, checkedAt: DateTime.now(),
                detail: err.toString(),
              ));
            }
          }
        }
      }

      // Only explicitly associated work pages, never entire homepages.
      final candidates = <(LibraryEntry, SavedSiteLink, CatalogSite, String)>[];
      final ids = <String>{};
      for (final e in watched) {
        for (final link in e.savedSiteLinks) {
          final site = siteById(link.siteId);
          if (site == null || !activeSources.any((s) => s.id == site.id) ||
              !settings.comicLangs.contains(link.lang) ||
              !site.accepts(link.url)) continue;
          if (site.hasReaderConnector) continue;
          if (!_recipes.forSite(site.id).canInspect) {
            _feedCheckResults.add(FeedCheckResult(
              workId: e.work.id, workTitle: e.work.title,
              sourceId: site.id, sourceName: site.title, language: link.lang,
              state: FeedCheckState.unavailable, checkedAt: DateTime.now(),
              detail: 'Ce site ne permet pas la lecture automatisee des listes.',
            ));
            continue;
          }
          final hash = sha256.convert(utf8.encode(link.url)).toString().substring(0, 16);
          final bucketId = 'listing:${site.id}:$hash';
          final scanId = '${e.work.id}|$bucketId|${link.lang}';
          if (ids.add(scanId)) candidates.add((e, link, site, scanId));
        }
      }
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      candidates.sort((a, b) =>
          (_lastListingChecks[a.$4] ?? epoch).compareTo(
              _lastListingChecks[b.$4] ?? epoch));
      var attempts = 0;
      for (final candidate in candidates) {
        if (!_active || attempts >= (forceSiteScan ? 20 : 10)) break;
        final (e, link, site, scanId) = candidate;
        final now = DateTime.now();
        final previous = _lastListingChecks[scanId];
        final minGap = Duration(seconds: forceSiteScan ? 10 : 1800);
        if (previous != null && now.difference(previous) < minGap) {
          _feedCheckResults.add(FeedCheckResult(
            workId: e.work.id, workTitle: e.work.title,
            sourceId: site.id, sourceName: site.title, language: link.lang,
            state: FeedCheckState.rateLimited, checkedAt: now,
            detail: 'Controle recent : patienter avant une nouvelle requete.',
          ));
          continue;
        }
        _lastListingChecks[scanId] = now;
        attempts++;
        listingChecks++;
        try {
          final list = await _listingFetcher.fetch(site: site, workUrl: link.url);
          final hash = sha256.convert(utf8.encode(link.url)).toString().substring(0, 16);
          final bucketId = 'listing:${site.id}:$hash';
          final chapters = ChapterListingParser.asChapters(
            list, bucketId: bucketId, language: link.lang, label: site.title,
          );
          final availability = ReadAvailability.calculate(e.progress, chapters);
          _feedCheckResults.add(FeedCheckResult(
            workId: e.work.id, workTitle: e.work.title,
            sourceId: site.id, sourceName: site.title, language: link.lang,
            state: FeedCheckState.checked, checkedAt: now,
            chapterCount: availability.total,
            unreadCount: availability.unread,
                unreadKeys: availability.unreadKeys,
            latestChapter: availability.latest,
            nextUnread: availability.nextUnread,
            nextUrl: availability.nextUrl,
            detail: 'Chapitres trouves sur la fiche publique.',
          ));
          final fresh = ReleaseDetector.observe(
            e, bucketId, chapters,
            langs: [link.lang], firstObservationIsBaseline: true,
          );
          for (final c in fresh) {
            final item = UpdateItem(
              workId: e.work.id, title: e.work.title,
              coverUrl: e.work.coverUrl, keyId: c.key.id,
              lang: link.lang, group: site.title,
              siteId: site.id, chapterUrl: c.externalUrl,
              foundAt: now, publishedAt: c.publishedAt,
            );
            if (known.add(item.id)) {
              _data.updates.insert(0, item);
              found++;
              _recordRelease(e, link.lang, now);
            }
          }
        } catch (err) {
          listingFailures++;
          lastListingError = '${site.title} : $err';
          final message = err.toString();
          _feedCheckResults.add(FeedCheckResult(
            workId: e.work.id, workTitle: e.work.title,
            sourceId: site.id, sourceName: site.title, language: link.lang,
            state: message.contains('429') ? FeedCheckState.rateLimited
                : FeedCheckState.failed,
            checkedAt: now, detail: message,
          ));
          AppLog.info('Liste de chapitres non verifiable pour ${e.work.title} '
              'sur ${site.title}: $err');
        }
      }
      // No fake "verified" results for unlinked or skipped sources.
      if (listingChecks > 0) lastListingCheckAt = DateTime.now();
      UpdateHygiene.clean(_data.updates, _data.entries);
      if (_data.updates.length > 500) {
        _data.updates.removeRange(500, _data.updates.length);
      }
      if (nativeFailures == 0) lastCheckError = null;
      _consecutiveFailures = nativeFailures > 0 ?
          (_consecutiveFailures + 1).clamp(0, 3).toInt() : 0;
      lastCheckAt = DateTime.now();
      unawaited(_saveLocatedReaders());
      _changed();
      AppLog.info('Sorties : $found nouvelles, $verifiedFeeds flux verifies, '
          '$failedFeeds en echec, $confirmedUnread chapitres non lus.');
      return found;
    } finally {
      checking = false;
      _scheduleAutoChecks();
      notifyListeners();
    }
  }

  void markUpdatesSeen({String? workId}) {
    for (final u in _data.updates) {
      if (workId == null || u.workId == workId) u.seen = true;
    }
    _changed();
  }

  // -------------------------------------------------------------------------
  // Réglages et sauvegardes
  // -------------------------------------------------------------------------

  void updateSettings(void Function(Settings s) change) {
    change(_data.settings);
    _applySourceSettings();
    _chapterCache.clear();
    _scheduleAutoChecks();
    _changed();
  }

  /// Association explicite d'une fiche de lecture a une oeuvre.
  /// La surveillance de metadonnees HTML reste possible uniquement sur les
  /// sources compatibles ; cela n'autorise ni la copie ni le DL de leurs pages.
  bool addSiteLink(WorkInfo work, String siteId, String url, String lang) {
    final site = siteById(siteId);
    if (site == null || !_recipes.forSite(site.id).accepts(site, url)) return false;
    final e = _data.entries[work.id] ?? addToLibrary(work);
    final cleanUrl = url.trim();
    if (e.savedSiteLinks.any((l) => l.siteId == siteId && l.url == cleanUrl)) return true;
    if (e.savedSiteLinks.isEmpty && !e.watch) {
      // Linking a work for the first time opts it into monitoring. The user
      // can still turn watching off independently from the saved URL.
      e.watch = true;
    }
    e.savedSiteLinks.add(SavedSiteLink(siteId: siteId, url: cleanUrl, lang: lang));
    _changed();
    return true;
  }

  void removeSiteLink(String workId, SavedSiteLink link) {
    final e = _data.entries[workId];
    if (e == null) return;
    e.savedSiteLinks.removeWhere((l) =>
        l.siteId == link.siteId && l.url == link.url);
    _changed();
  }

  String exportBackup() => LibraryStore.encodeBackup(_data, appVersion);

  /// Vérifie puis fusionne une sauvegarde. Lève [FormatException] si invalide.
  MergeReport importBackup(String text) {
    final incoming = LibraryStore.decodeBackup(text);
    final report = LibraryStore.merge(_data, incoming);
    _data.settings = incoming.settings;
    _applySourceSettings();
    _chapterCache.clear();
    _changed();
    return report;
  }


  // -------------------------------------------------------------------------
  // Moteur Pazulu 2.0 : extensions, routage, diagnostics
  // -------------------------------------------------------------------------

  Future<void> _initEngine(Directory dir) async {
    final texts = <String>[];
    try {
      final index = jsonDecode(await rootBundle.loadString('assets/extensions/index.json'));
      final files = index is Map && index['files'] is List ? index['files'] as List : const [];
      for (final f in files) {
        if (f is String && f.startsWith('assets/extensions/')) {
          texts.add(await rootBundle.loadString(f));
        }
      }
    } catch (e) {
      AppLog.error('Extensions integrees introuvables', e);
    }
    try {
      extensionWarnings = await engine.init(dir, texts);
    } catch (e, st) {
      AppLog.error('Initialisation du moteur Pazulu 2.0', e, st);
    }
    engine.log.onEntry = (entry) {
      if (entry.level.index >= 2) {
        AppLog.info('[moteur] ${entry.event} ${entry.sourceId ?? ''} ${entry.message ?? ''}');
      }
    };
    _applyExtensions();
  }

  /// Registers the enabled extensions as sources, unregisters disabled ones.
  /// Never touches the library, progress or downloaded chapters.
  void _applyExtensions() {
    final natives = <String, ContentSource>{
      'mangadex': _mangadex,
      'peppercarrot': _peppercarrot,
      'sushiscan_net': _sushiscan,
    };
    for (final entry in natives.entries) {
      if (engine.nativeEnabled(entry.key)) {
        sources.register(entry.value);
      } else {
        sources.unregister(entry.key);
      }
    }
    for (final id in _declarativeIds) {
      sources.unregister(id);
    }
    _declarativeIds.clear();
    for (final source in engine.buildDeclarativeSources()) {
      if (natives.containsKey(source.id) || source.id == _captures.id) continue;
      sources.register(source);
      _declarativeIds.add(source.id);
    }
    _chapterCache.clear();
    _chapterCachedAt.clear();
  }

  List<InstalledExtension> get installedExtensions =>
      engine.extensions?.all ?? const [];

  /// Reads a .pazulusource / .pazulupack WITHOUT installing it, so the UI
  /// can show integrity and origin before the user confirms.
  LoadedPack previewExtensionPack(Uint8List bytes, String fileName) =>
      engine.readPack(bytes, fileName);

  Future<InstallReport> installExtensionPack(LoadedPack pack) async {
    final registry = engine.extensions;
    if (registry == null) throw StateError('Moteur non initialise.');
    final report = await registry.install(pack);
    _applyExtensions();
    engine.log.info('extension_installed',
        message: '${report.installed.length} ajoutee(s), ${report.updated.length} mise(s) a jour');
    notifyListeners();
    return report;
  }

  Future<void> setExtensionEnabled(String id, bool enabled) async {
    await engine.extensions?.setEnabled(id, enabled);
    _applyExtensions();
    notifyListeners();
  }

  Future<bool> rollbackExtension(String id) async {
    final ok = await engine.extensions?.rollback(id) ?? false;
    _applyExtensions();
    notifyListeners();
    return ok;
  }

  Future<bool> removeExtension(String id) async {
    final ok = await engine.extensions?.remove(id) ?? false;
    _applyExtensions();
    notifyListeners();
    return ok;
  }

  /// Sources shown in « Diagnostic des sources »: every real connector,
  /// with or without a manifest, plus disabled extensions.
  List<(String id, String name, ContentSource? source, InstalledExtension? ext)>
      diagnosticEntries() {
    final out = <(String, String, ContentSource?, InstalledExtension?)>[];
    final seen = <String>{};
    for (final s in sources.all) {
      if (s is PublicCatalogSource || s.id == _captures.id) continue;
      seen.add(s.id);
      out.add((s.id, s.name, s, engine.extensionForSource(s.id)));
    }
    for (final e in installedExtensions) {
      final sourceId = e.manifest.nativeAdapter ?? e.manifest.id;
      if (seen.contains(sourceId)) continue;
      out.add((sourceId, e.manifest.name, null, e));
    }
    out.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return out;
  }

  ConnectorStats connectorStats(String sourceId) => engine.health.of(sourceId);

  final Set<String> testingSources = {};

  Future<SourceTestReport> testSource(String sourceId) async {
    final source = sources.byId(sourceId);
    if (source == null) {
      throw const SourceException('Extension desactivee : activez-la avant le test.');
    }
    testingSources.add(sourceId);
    notifyListeners();
    try {
      return await engine.testSource(source, languages: settings.comicLangs);
    } finally {
      testingSources.remove(sourceId);
      notifyListeners();
    }
  }

  String exportEngineDiagnostics() => engine.exportDiagnostics();

  /// Smart Source Router entry point used by the reader.
  Future<RouteOutcome> routeChapter({
    required WorkInfo work,
    required SourceChapter requested,
    required List<SourceChapter> candidates,
    int startIndex = 0,
    Set<int> exclude = const {},
    Set<int> userConfirmed = const {},
    bool? autoFallback,
    void Function(RouteStep step)? onStep,
    CancelToken? cancel,
  }) async {
    final outcome = await engine.router.route(
      requested: requested,
      candidates: candidates,
      lookup: sources.byId,
      startIndex: startIndex,
      exclude: exclude,
      userConfirmed: userConfirmed,
      autoFallback: autoFallback ?? settings.autoFailover,
      allowOtherLanguages: settings.crossLanguageFallback,
      preferredLanguages: settings.comicLangs,
      edition: editionOf(work),
      isOffline: (c) => downloadOf(c.chapterId) != null,
      onStep: onStep,
      cancel: cancel,
    );
    for (final step in outcome.steps) {
      if (step.state == RouteStepState.restricted ||
          step.state == RouteStepState.unavailable ||
          step.state == RouteStepState.partial ||
          step.state == RouteStepState.invalid) {
        reportChapterFailure(step.chapter, step.message);
      }
    }
    unawaited(engine.saveHealth().catchError((Object e) {
      AppLog.error('Sante des connecteurs', e);
    }));
    return outcome;
  }

  /// Validated pages from any path (API, HTML, WebView2 capture) feed the
  /// diagnostics: FULL_READER is only shown after a real validated read.
  void recordValidatedRead(SourceChapter chapter, ChapterPages pages) {
    engine.recordReaderOutcome(chapter, pages);
    unawaited(engine.saveHealth().catchError((Object e) {
      AppLog.error('Sante des connecteurs', e);
    }));
  }

  /// « Rechercher une autre source » : metadata-only lookup of the same work
  /// in the other connectors, then the fresh variants of [key].
  Future<(ReaderLookupReport, List<SourceChapter>)> searchAlternativeReaders(
      WorkInfo work, ChapterKey key) async {
    final report = await locateNativeReaders(work);
    final groups = await chaptersFor(work, refresh: true);
    for (final g in groups) {
      if (g.key == key) return (report, g.variants);
    }
    return (report, const <SourceChapter>[]);
  }

  SourceStatus? lastKnownStatus(String sourceId) =>
      engine.health.stats[sourceId]?.lastTest?.status;

  /// Per-work reading direction chosen by the user (null = automatic).
  void setReaderModeOverride(WorkInfo work, ReaderMode? mode) {
    final e = _data.entries[work.id] ?? addToLibrary(work, status: TrackStatus.reading);
    e.readerModeOverride = mode;
    _changed();
  }

  ContentSource? sourceOf(SourceChapter c) => sources.byId(c.sourceId);

  /// Mise a jour declarative des connecteurs, sans executer de code tiers.
  /// Le pack ne peut jamais changer les domaines ou activer une source officielle.
  Future<int> importSourceRecipes(String json) async {
    final next = SourceRecipeRegistry.defaults();
    next.mergeManifest(_recipes.exportJson());
    final count = next.mergeManifest(json);
    await _recipeStore?.save(next);
    _recipes = next;
    notifyListeners();
    return count;
  }

  /// Les pages sont conservees en memoire pendant la session puis, si
  /// l'utilisateur le choisit, sauvegardees avec downloadChapter en CBZ.
  (WorkInfo, SourceChapter) registerBrowserCapture(
      CatalogSite site, PageInspection inspection, String lang, {
      WorkInfo? existingWork, ChapterKey? chapterKey}) {
    if (!_recipes.forSite(site.id).accepts(site, inspection.pageUrl) ||
        !_recipes.forSite(site.id).canInspect ||
        !const ['fr', 'en'].contains(lang)) {
      throw const FormatException('Source ou langue non autorisee.');
    }
    final hash = sha256.convert(utf8.encode(inspection.pageUrl)).toString().substring(0, 20);
    final key = chapterKey ?? ChapterIdentity.detect(
      title: inspection.title, url: inspection.pageUrl,
    );
    if (key == null) {
      throw const FormatException('Numero de chapitre introuvable : indique-le pour lier la progression.');
    }
    final workId = existingWork?.id ?? 'capture:${site.id}:$hash';
    final previous = _data.entries[workId]?.work ?? existingWork;
    final links = <SourceLink>[...?previous?.links];
    if (!links.any((l) => l.sourceId == _captures.id && l.workId == workId)) {
      links.add(SourceLink(sourceId: _captures.id, workId: workId));
    }
    final WorkInfo work;
    if (previous != null) {
      work = WorkInfo.fromJson({
        ...previous.toJson(),
        'links': links.map((l) => l.toJson()).toList(),
      });
    } else {
      work = WorkInfo(
        id: workId,
        title: inspection.title.isEmpty ? site.title : inspection.title,
        type: ContentType.manhwa,
        languages: [lang], longStrip: true, links: links,
      );
    }
    final chapter = SourceChapter(
      sourceId: _captures.id,
      chapterId: 'capture:${site.id}:$hash:${key.id}:$lang',
      key: key, lang: lang, group: site.title,
      title: inspection.title, pages: inspection.pages.length,
    );
    _captures.add(workId, chapter, inspection.pages);
    final entry = _data.entries[workId] ??
        addToLibrary(work, status: TrackStatus.reading);
    entry.work = work;
    // Do not attach a chapter URL as a work listing; those are distinct.
    _chapterCache.remove(workId);
    _changed();
    return (work, chapter);
  }

  /// Les CBZ/ZIP d'un autre site rejoignent la MEME œuvre et la MEME
  /// progression, au lieu de creer une copie de l'œuvre dans la bibliotheque.
  Future<int> importArchivesForWork(
    WorkInfo work,
    List<String> paths, {
    required String language,
    String sourceLabel = 'Archive personnelle',
    String? singleChapterNumber,
  }) async {
    final store = _downloads;
    if (store == null) throw StateError('Bibliotheque hors ligne indisponible.');
    final count = await store.importIntoWork(
      work: work, paths: paths, language: language,
      sourceLabel: sourceLabel, singleChapterNumber: singleChapterNumber,
    );
    addToLibrary(work, status: TrackStatus.reading);
    _chapterCache.remove(work.id);
    _changed();
    return count;
  }

  // -------------------------------------------------------------------------
  // Hors ligne
  // -------------------------------------------------------------------------

  DownloadRecord? downloadOf(String chapterId) => _downloads?.byChapter(chapterId);

  List<DownloadRecord> downloadsFor(String workId) => _downloads?.forWork(workId) ?? const [];

  int get downloadCount => _downloads?.all.length ?? 0;

  int get downloadBytes => _downloads?.totalBytes ?? 0;

  String? get downloadsPath => _downloads?.dir.path;

  /// Returns a cached chapter or downloads it on explicit reader entry.
  /// Search, work summaries and chapter lists never call this method.
  Future<DownloadRecord?> prepareChapterForReading(
    WorkInfo work, SourceChapter chapter,
  ) async {
    final cached = downloadOf(chapter.chapterId);
    if (cached != null) return cached;
    if (chapter.isExternal || !settings.cacheOnRead) return null;
    if (sourceOf(chapter) == null) return null;
    await downloadChapter(work, chapter);
    return downloadOf(chapter.chapterId);
  }

  /// Downloads one chapter, coalescing parallel calls from the same source.
  /// An explicit download is also available when auto-cache is switched off.
  Future<void> downloadChapter(WorkInfo work, SourceChapter chapter) async {
    if (downloadOf(chapter.chapterId) != null) return;
    final existing = _downloadTasks[chapter.chapterId];
    if (existing != null) {
      await existing;
      return;
    }
    final store = _downloads;
    final source = sourceOf(chapter);
    if (store == null || source == null || chapter.isExternal) {
      throw const SourceException('Aucune source de pages compatible pour ce chapitre.');
    }
    final task = _downloadChapterNow(work, chapter, store, source);
    _downloadTasks[chapter.chapterId] = task;
    try {
      await task;
    } finally {
      _downloadTasks.remove(chapter.chapterId);
    }
  }

  Future<void> _downloadChapterNow(
    WorkInfo work, SourceChapter chapter,
    DownloadStore store, ContentSource source,
  ) async {
    downloading[chapter.chapterId] = 0;
    notifyListeners();
    try {
      await store.download(
        work: work,
        chapter: chapter,
        source: source,
        onProgress: (p) {
          // The whole app rebuilds on notify: only every 20 % (was every
          // page, a cause of stutter while reading).
          final before = downloading[chapter.chapterId] ?? 0;
          downloading[chapter.chapterId] = p;
          if ((p * 5).floor() != (before * 5).floor() || p >= 1) notifyListeners();
        },
      );
      AppLog.info('Chapitre conserve a la premiere lecture : '
          '${work.title} ${chapter.key.label} (${chapter.lang})');
    } finally {
      downloading.remove(chapter.chapterId);
      notifyListeners();
    }
  }

  /// Importe des fichiers .cbz / .zip et les ajoute à la bibliothèque.
  Future<int> importLocalFiles(List<String> paths) async {
    final store = _downloads;
    if (store == null || paths.isEmpty) return 0;
    final works = await store.importLocal(paths);
    for (final w in works) {
      final existing = _data.entries[w.id];
      if (existing == null) {
        _data.entries[w.id] = LibraryEntry(work: w, status: TrackStatus.reading, watch: false);
      }
      _chapterCache.remove(w.id);
    }
    _changed();
    return works.length;
  }

  Future<void> deleteDownload(String chapterId) async {
    await _downloads?.delete(chapterId);
    notifyListeners();
  }

  Future<List<Uint8List>> offlinePages(DownloadRecord r) =>
      _downloads?.readPages(r) ?? Future.value(const <Uint8List>[]);

  @override
  void dispose() {
    _disposed = true;
    _frSave?.cancel();
    _onlineTimer?.cancel();
    _brokenTimer?.cancel();
    _trailingNotify?.cancel();
    _quietNotify?.cancel();
    engine.dispose();
    _checkTimer?.cancel();
    _healthTimer?.cancel();
    _saveTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }
}

class BookmarkImportReport {
  const BookmarkImportReport({
    required this.links,
    required this.readings,
    required this.added,
    required this.updated,
    required this.positioned,
  });

  final int links;
  final int readings;
  final int added;
  final int updated;
  final int positioned;
}
