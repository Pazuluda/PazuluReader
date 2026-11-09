import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/chapters.dart';
import '../core/downloads.dart' show DownloadRecord;
import '../core/log.dart';
import '../core/models.dart';
import '../core/source.dart';
import '../core/visible_pages.dart';
import '../core/chapter_pagination.dart';
import '../core/reader_failover.dart';
import '../core/browser_page_turn.dart';
import '../core/browser_navigation.dart';
import '../design/theme.dart';
import '../engine/availability.dart';
import '../engine/diagnostics/source_status.dart';
import '../engine/http/engine_http.dart' show CancelToken;
import '../engine/routing/smart_router.dart';
import '../engine/source_contract.dart';
import '../engine/validation/access_detector.dart';
import '../engine/validation/page_validation.dart';
import 'app_scope.dart';
import 'widgets/common.dart';
import 'widgets/reader_switcher.dart';
import 'source_browser_page.dart';
import 'widgets/official_web_view.dart';

/// Lecteur d'images : vertical continu (webtoon) ou pages (G→D / D→G).
/// Sélecteur « Lecteur 1 / Lecteur 2… » pour changer de source à la volée.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.work,
    required this.groups,
    required this.initialIndex,
    this.initialPage = 0,
    this.initialVariant,
  });

  final WorkInfo work;

  /// Chapitres triés par ordre croissant.
  final List<ChapterGroup> groups;
  final int initialIndex;
  final int initialPage;

  /// Lecteur choisi depuis la fiche (sinon : le Lecteur 1).
  final SourceChapter? initialVariant;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _started = false;
  bool _siteReader = false;
  bool _siteProbeBusy = false;
  int _sitePagesFound = 0;
  int? _sitePagesExpected;
  int _siteCaptureGeneration = 0;
  EmbeddedBrowserBridge? _siteBridge;
  late AppState _app;
  late int _index;
  List<SourceChapter> _variants = const [];
  int _variant = 0;
  final Set<int> _failedVariants = {};

  // Moteur 2.0 ---------------------------------------------------------------
  late List<ChapterGroup> _groups;
  /// The chapter the user asked for: fallbacks must be ITS equivalents.
  SourceChapter? _requested;
  final List<RouteStep> _routeSteps = [];
  List<int> _needsConfirmation = const [];
  final Set<int> _confirmed = {};
  final Set<int> _verifiedVariants = {};
  Map<String, String> _routeHeaders = const {};
  CancelToken? _cancel;
  bool _searchingAlternatives = false;
  String? _alternativesNote;
  bool _manualSwitch = false;
  bool _doublePage = false;
  PageFit _fit = PageFit.contain;

  List<PageRef>? _pages;

  /// Pages lues depuis un téléchargement hors ligne (.cbz), sinon null.
  List<Uint8List>? _localPages;
  Object? _error;
  bool _loading = true;
  int _loadToken = 0;

  int _page = 0;
  int _startPage = 0;
  final Set<int> _useFallback = {};
  final Set<int> _brokenImagesHandled = {};
  final Set<int> _decodedPages = {};
  List<GlobalKey> _keys = const [];

  late ReaderMode _mode;
  bool _uiVisible = true;

  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  PageController? _pager;
  final FocusNode _focus = FocusNode(debugLabel: 'reader');
  Timer? _saveTimer;

  /// Hides the controls a moment after the pages appear: the page is read
  /// without anything on top of it (tap to bring the controls back).
  Timer? _hideTimer;
  bool _hideArmed = false;
  Timer? _siteStartupTimer;
  bool _probeScheduled = false;

  ChapterGroup get _group => _groups[_index];
  SourceChapter? get _current =>
      _variants.isEmpty ? null : _variants[_variant.clamp(0, _variants.length - 1)];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _app = AppScope.read(context);
    _app.readerOpened();
    _seenRevision = _app.readerRevision(widget.work.id);
    _app.addListener(_onAppChanged);
    final app = _app;
    _groups = List<ChapterGroup>.of(widget.groups);
    _doublePage = app.settings.doublePage;
    _fit = app.settings.pageFit;
    // Automatic direction (webtoon = vertical), overridable per work.
    _mode = app.entry(widget.work.id)?.readerModeOverride ??
        (widget.work.longStrip ? ReaderMode.vertical : app.settings.readerMode);
    _openChapter(widget.initialIndex, startPage: widget.initialPage, prefer: widget.initialVariant);
  }

  @override
  void dispose() {
    if (_started) {
      _app.removeListener(_onAppChanged);
      _app.readerClosed();
    }
    _flushSave(deferred: true);
    _cancel?.cancel();
    _siteStartupTimer?.cancel();
    _hideTimer?.cancel();
    _scroll.dispose();
    _pager?.dispose();
    _focus.dispose();
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Chargement
  // -------------------------------------------------------------------------
  // Sources found while reading: the open chapter and the next ones get them
  // at once (no need to leave and reopen the chapter).

  int _seenRevision = 0;
  bool _refreshingGroups = false;

  void _onAppChanged() {
    final rev = _app.readerRevision(widget.work.id);
    if (rev == _seenRevision || _refreshingGroups || !mounted) return;
    _seenRevision = rev;
    _refreshGroups();
  }

  Future<void> _refreshGroups() async {
    _refreshingGroups = true;
    try {
      final fresh = await _app.chaptersFor(widget.work);
      if (!mounted || fresh.isEmpty || _groups.isEmpty) return;
      final currentKey = _groups[_index].key.id;
      final newIndex = fresh.indexWhere((g) => g.key.id == currentKey);
      if (newIndex < 0) return;
      final app = _app;
      final routed = app.usableReaders(
          rankVariants(fresh[newIndex].variants,
              langs: app.settings.comicLangs,
              preferredLang: app.preferredLangOf(widget.work.id)),
          preferredLang: app.preferredLangOf(widget.work.id));
      final added = [
        for (final v in routed)
          if (!_variants.any((o) => o.sourceId == v.sourceId && o.chapterId == v.chapterId)) v,
      ];
      setState(() {
        _groups = List<ChapterGroup>.of(fresh);
        _index = newIndex;
        // Appended: the indexes of the readers already tried stay valid.
        if (added.isNotEmpty) _variants = [..._variants, ...added];
      });
      // The chapter could not be opened: try the reader that just arrived.
      if (added.isNotEmpty && _error != null) {
        final i = _variants.indexWhere((v) => added.contains(v) && app.isPazuluReadable(v));
        if (i >= 0) _switchVariant(i, keepPage: false);
      }
      if (added.isNotEmpty) {
        AppLog.info('Lecteur : ${added.length} lecteur(s) ajouté(s) pendant la lecture de '
            '${widget.work.title} ${_groups[_index].key.longLabel}');
      }
    } catch (_) {
      // The current list stays.
    } finally {
      _refreshingGroups = false;
    }
  }

  void _openChapter(int index, {int startPage = 0, SourceChapter? prefer}) {
    _flushSave();
    _siteStartupTimer?.cancel();
    final app = _app;
    final entry = app.entry(widget.work.id);
    final ranked = rankVariants(
      _groups[index].variants,
      langs: app.settings.comicLangs,
      preferredLang: app.preferredLangOf(widget.work.id),
      preferredGroup: entry?.preferredGroup,
      preferredSourceId: entry?.preferredSourceId,
    );
    // A broken reader or catalogue-only source must not block an offline
    // copy or another real connector. External links come last.
    final routed = app.usableReaders(ranked,
        preferredSourceId: entry?.preferredSourceId,
        preferredLang: app.preferredLangOf(widget.work.id));
    final preferred = prefer == null
        ? -1
        : routed.indexWhere((v) => v.sourceId == prefer.sourceId && v.chapterId == prefer.chapterId);
    setState(() {
      _index = index;
      _siteReader = false;
      _siteCaptureGeneration++;
      _siteProbeBusy = false;
      _sitePagesFound = 0;
      _sitePagesExpected = null;
      _siteBridge = null;
      _variants = routed;
      _variant = preferred >= 0 && app.isPazuluReadable(routed[preferred])
          ? preferred
          : (routed.indexWhere(app.isPazuluReadable) < 0
              ? 0 : routed.indexWhere(app.isPazuluReadable));
      _failedVariants.clear();
      _startPage = startPage;
      _routeSteps.clear();
      _needsConfirmation = const [];
      _confirmed.clear();
      _verifiedVariants.clear();
      _routeHeaders = const {};
      _alternativesNote = null;
      _manualSwitch = false;
    });
    _requested = _current;
    final wanted = app.preferredLangOf(widget.work.id);
    final opened = _current;
    if (wanted != null && opened != null && opened.lang != wanted) {
      // Said clearly instead of silently reading another language.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_group.key.longLabel} : pas encore de version '
              '${wanted.toUpperCase()} lisible, ouverture en ${opened.lang.toUpperCase()}.'),
        ));
      });
    }
    _loadPages();
  }

  void _switchVariant(int i, {bool keepPage = true}) {
    if (i == _variant || i < 0 || i >= _variants.length) return;
    _siteStartupTimer?.cancel();
    _failedVariants.remove(i); // Explicit click always permits a new attempt.
    final keepPosition = _pages != null ? _page : _startPage;
    setState(() {
      _variant = i;
      _siteReader = false;
      _siteCaptureGeneration++;
      _siteProbeBusy = false;
      _sitePagesFound = 0;
      _sitePagesExpected = null;
      _siteBridge = null;
      // The new reader might have a different page count. Clamp after its
      // pages are known instead of needlessly restarting at page zero.
      _startPage = keepPage ? keepPosition : 0;
      _manualSwitch = true;
    });
    // An explicit choice becomes the reference chapter for later fallbacks.
    _requested = _current;
    _loadPages();
  }

  Future<void> _loadPages() async {
    final token = ++_loadToken;
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;
    final v = _current;
    setState(() {
      _pages = null;
      _error = null;
      _loading = true;
      _useFallback.clear();
      _brokenImagesHandled.clear();
      _decodedPages.clear();
      _localPages = null;
      _routeSteps.clear();
      _routeHeaders = const {};
    });
    if (v == null) {
      setState(() {
        _loading = false;
        _error = const _ReaderError('Aucune version disponible pour ce chapitre.');
      });
      return;
    }
    // Wait until the current build frame completes before notifying app-wide
    // download progress listeners. This avoids markNeedsBuild during build.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || token != _loadToken) return;
    if (v.isExternal) {
      setState(() {
        _pages = const [];
        _loading = false;
        _uiVisible = true;
      });
      // External catalogue entries do not contain pages and are not a read.
      return;
    }
    final app = _app;
    try {
      final offline = app.downloadOf(v.chapterId);
      if (offline != null) {
        try {
          await _showOffline(v, offline, token);
          return;
        } on ChapterValidationException catch (e) {
          // Incomplete offline copy: deleted, then the chapter is read online
          // (the copy used to fail the same way at every opening).
          AppLog.info('Copie hors ligne incomplète supprimée (${v.key.longLabel}, ${v.group}) : ${e.message}');
          await app.deleteDownload(v.chapterId);
          if (!mounted || token != _loadToken) return;
        }
      }
      // Smart Source Router: resolution, validation of real images and, if
      // enabled, fallback to a TRUE equivalent of the requested chapter.
      final outcome = await app.routeChapter(
        work: widget.work,
        requested: _requested ?? v,
        candidates: _variants,
        startIndex: _variant,
        exclude: Set<int>.of(_failedVariants),
        userConfirmed: _confirmed,
        cancel: cancel,
        onStep: (step) {
          if (!mounted || token != _loadToken) return;
          setState(() => _routeSteps.add(step));
        },
      );
      if (!mounted || token != _loadToken) return;
      for (final step in outcome.steps) {
        if (step.state == RouteStepState.restricted ||
            step.state == RouteStepState.unavailable ||
            step.state == RouteStepState.partial ||
            step.state == RouteStepState.invalid ||
            step.state == RouteStepState.skippedPaused) {
          _failedVariants.add(step.index);
        }
      }
      _needsConfirmation = outcome.confirmationCandidates;
      final selected = outcome.selectedIndex;
      if (selected == null) {
        setState(() {
          _pages = const <PageRef>[];
          _localPages = null;
          _loading = false;
          _error = _ReaderError(_noReaderMessage(outcome));
        });
        return;
      }
      if (selected != _variant) {
        final from = _variant;
        setState(() => _variant = selected);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lecteur ${from + 1} indisponible. Passage automatique au '
              'Lecteur ${selected + 1} (${_sourceLabel(_variants[selected])}).'),
        ));
      }
      final chosen = _variants[selected];
      final cached = app.downloadOf(chosen.chapterId);
      if (cached != null) {
        try {
          await _showOffline(chosen, cached, token);
          return;
        } on ChapterValidationException catch (e) {
          // An incomplete offline copy is deleted and the chapter is read
          // online, instead of failing the same way at every opening.
          AppLog.info('Copie hors ligne incomplète supprimée (${chosen.key.longLabel}) : ${e.message}');
          await app.deleteDownload(chosen.chapterId);
          if (!mounted || token != _loadToken) return;
          unawaited(_loadPages());
          return;
        }
      }
      if (outcome.needsBrowser) {
        if (!_browserAllowed(chosen)) {
          _routeAfterFailure(SourceException('${chosen.group} (${chosen.lang.toUpperCase()}) : '
              'pages pas encore lisibles par le lecteur Pazulu, autre lecteur essayé.'));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                '${_group.key.longLabel} : la version ${chosen.lang.toUpperCase()} existe sur '
                '${chosen.group}, mais ses pages ne sont pas encore lisibles ici. '
                'Page enregistrée pour ajouter ce site.')));
          }
          return;
        }
        setState(() {
          _siteReader = true;
          _siteBridge = null;
          _sitePagesFound = 0;
          _sitePagesExpected = null;
          _loading = false;
          _routeHeaders = {'Referer': chosen.chapterId};
        });
        _armSiteStartupTimeout();
        return;
      }
      final resolved = outcome.pages!;
      _verifiedVariants.add(selected);
      app.reportChapterSuccess(chosen);
      app.recordValidatedRead(chosen, resolved);
      _showPages(resolved.pages, headers: resolved.imageHeaders);
      _rememberManualChoice(chosen);
      // First page first: the CBZ copy is made afterwards, in background.
      if (app.settings.cacheOnRead && resolved.transport != 'browser') {
        unawaited(app.downloadChapter(widget.work, chosen).catchError((Object e) {
          AppLog.info('Mise en cache en arriere-plan impossible : $e');
        }));
      }
    } catch (e, st) {
      AppLog.error('Chargement du chapitre ${_group.key.id} (${v.group})', e, st);
      if (!mounted || token != _loadToken) return;
      _routeAfterFailure(e);
    }
  }

  /// Offline CBZ: the stored bytes themselves are validated (real images,
  /// no HTML error page saved by mistake, no repeated image).
  static Future<ChapterPages> _validateOffline(List<Uint8List> local, bool longStrip) =>
      Isolate.run(() => const PageValidationEngine().evaluate(
            [for (var i = 0; i < local.length; i++) PageRef('hors-ligne:$i')],
            announcedTotal: null,
            probes: [
              for (var i = 0; i < local.length; i++)
                PageProbe.fromBytes(i, 'hors-ligne:$i', 200, local[i], complete: true),
            ],
            offline: true,
            policy: longStrip ? ValidationPolicy.webtoon : ValidationPolicy.strict,
            transport: 'offline',
          ));

  Future<void> _showOffline(SourceChapter chapter, DownloadRecord record, int token) async {
    final local = await _app.offlinePages(record);
    if (!mounted || token != _loadToken) return;
    final refs = [for (var i = 0; i < local.length; i++) PageRef('hors-ligne:$i')];
    // Checking every image of a long copy (147 pages: hashes, headers) took
    // seconds on the screen's thread: black window. Done in background.
    final verdict = await _validateOffline(local, widget.work.longStrip);
    if (!mounted || token != _loadToken) return;
    // A copy of a chapter read online keeps its separators, credit pages and
    // thin webtoon slices: only a copy made mostly of non-images (error page,
    // paywall) or with too few valid pages is rejected. Before 2.3.6 such
    // copies were deleted and downloaded again on every opening.
    final mostlyValid = verdict.completeness == PageCompleteness.partial &&
        local.length >= 3 && verdict.validCount >= (local.length * 0.7).ceil();
    if (!verdict.readable && !mostlyValid) {
      throw ChapterValidationException(
          'Copie hors ligne invalide (${verdict.summary}).', result: verdict);
    }
    _app.reportChapterSuccess(chapter);
    _verifiedVariants.add(_variant);
    _showPages(refs, local: local);
  }

  void _showPages(List<PageRef> pages, {List<Uint8List>? local,
      Map<String, String> headers = const {}}) {
    AppLog.info('Lecteur : ${widget.work.title} ${_group.key.longLabel} · '
        '${_current == null ? '?' : _sourceLabel(_current!)} · ${pages.length} pages'
        '${local != null ? ' (hors ligne)' : ''}');
    _pager?.dispose();
    final start = pages.isEmpty ? 0 : _startPage.clamp(0, pages.length - 1);
    setState(() {
      _localPages = local;
      _pages = pages;
      _loading = false;
      _error = null;
      _page = start;
      _routeHeaders = headers;
      _keys = List.generate(pages.length, (_) => GlobalKey());
      _pager = PageController(initialPage: _pagerIndexFor(start));
    });
    if (_mode == ReaderMode.vertical && start > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPage(start));
    }
    // Do not persist a "read" state before a real image decodes.
    _precacheAround(start);
    _hideTimer?.cancel();
    _hideArmed = false;
  }

  void _rememberManualChoice(SourceChapter chosen) {
    if (!_manualSwitch) return;
    _manualSwitch = false;
    // « Mémoriser le choix par œuvre » : an explicit, successful choice.
    _app.setPreferredVariant(widget.work, chosen);
  }

  String _sourceLabel(SourceChapter c) {
    final name = _app.sourceOf(c)?.name ?? c.sourceId;
    return '$name · ${c.langLabel}';
  }

  bool _browserAllowed(SourceChapter chapter) {
    // The hidden WebView2 is a native window above the app: off unless the
    // user enabled it (black-screen risk); other readers are used instead.
    if (!_app.settings.browserReader) return false;
    final source = _app.sourceOf(chapter);
    final uri = safeReadingUri(chapter.chapterId);
    if (source is! BrowserRenderedSource || uri == null) return false;
    final host = uri.host.toLowerCase();
    return source.browserHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  String _noReaderMessage(RouteOutcome outcome) {
    final tried = outcome.steps.where((s) =>
        s.state != RouteStepState.checking && s.state != RouteStepState.confirmed).toList();
    final buffer = StringBuffer('Aucun lecteur n\'a fourni ce chapitre avec des '
        'pages valides.');
    if (!_app.settings.autoFailover && _variants.length > 1) {
      buffer.write(' Le basculement automatique est désactivé : choisissez un '
          'autre lecteur ci-dessus.');
    }
    if (outcome.confirmationCandidates.isNotEmpty) {
      buffer.write(' Des versions portant le même numéro existent, mais leur '
          'édition doit être confirmée (pastille jaune).');
    }
    if (tried.isEmpty && _variants.length <= 1) {
      buffer.write(' Un seul lecteur est connu : utilisez « Rechercher une autre source ».');
    }
    return buffer.toString();
  }

  int get _step => _spread ? 2 : 1;

  bool get _spread => _doublePage && _mode != ReaderMode.vertical &&
      (_pages?.length ?? 0) > 1;

  int _pagerIndexFor(int page) => _doublePage && _mode != ReaderMode.vertical
      ? page ~/ 2 : page;

  /// Next reader to try: another reader of the SAME language first (FR
  /// chosen = the other FR sites before any English one).
  int? _nextWorkingVariant() {
    final lang = _variant >= 0 && _variant < _variants.length ? _variants[_variant].lang : null;
    for (var i = 0; i < _variants.length; i++) {
      if (i == _variant || _failedVariants.contains(i)) continue;
      if (_variants[i].lang == lang && _app.isPazuluReadable(_variants[i])) return i;
    }
    return ReaderFailover.next(_variants,
      current: _variant,
      failed: _failedVariants,
      canRead: _app.isPazuluReadable,
    );
  }

  int? _otherWorkingVariant() => _nextWorkingVariant();

  /// Shared failure handling: metadata, HTML/WebView2, timeout and decoded
  /// image failures all use the same native/offline source switching policy.
  void _routeAfterFailure(Object failure) {
    if (!mounted) return;
    final broken = _current;
    if (broken != null) _app.reportChapterFailure(broken, failure);
    final from = _variant;
    _failedVariants.add(from);
    final next = _app.settings.autoFailover ? _nextWorkingVariant() : null;
    _siteStartupTimer?.cancel();
    // Invalidate the previous asynchronous WebView callbacks immediately.
    _siteCaptureGeneration++;
    if (next != null) {
      setState(() {
        _siteReader = false;
        _siteBridge = null;
        _siteProbeBusy = false;
        _sitePagesExpected = null;
        _sitePagesFound = 0;
        _startPage = _pages == null || _pages!.isEmpty ? _startPage : _page;
        _variant = next;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lecteur ${from + 1} indisponible. '
            'Recherche du même chapitre sur le Lecteur ${next + 1} '
            '(${_sourceLabel(_variants[next])}).'),
      ));
      unawaited(_loadPages());
      return;
    }
    setState(() {
      _siteReader = false;
      _siteBridge = null;
      _siteProbeBusy = false;
      _sitePagesExpected = null;
      _pages = const <PageRef>[];
      _localPages = null;
      _loading = false;
      _error = _ReaderError(_failureText(failure));
    });
  }

  void _onDecodedImage(int imageIndex, String chapterId) {
    if (_decodedPages.contains(imageIndex)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current?.chapterId != chapterId ||
          _pages == null || imageIndex >= _pages!.length) return;
      _decodedPages.add(imageIndex);
      // Controls hide only once a page is REALLY visible: never a black
      // screen without controls while images are still loading.
      if (!_hideArmed) {
        _hideArmed = true;
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted && _uiVisible && _error == null) setState(() => _uiVisible = false);
        });
      }
      // The last page is only "read" after that page has decoded, not
      // simply because the user navigated to its index.
      if (_page == imageIndex) _scheduleSave();
    });
  }

  void _onBrokenImage(int imageIndex, String chapterId) {
    if (_brokenImagesHandled.contains(imageIndex)) return;
    _brokenImagesHandled.add(imageIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current?.chapterId != chapterId ||
          _pages == null || imageIndex >= _pages!.length) return;
      final page = _pages![imageIndex];
      if (page.fallbackUrl != null && !_useFallback.contains(imageIndex)) {
        setState(() {
          _useFallback.add(imageIndex);
          _brokenImagesHandled.remove(imageIndex);
        });
      } else {
        _routeAfterFailure(SourceException('Image ${imageIndex + 1} '
            'impossible a afficher pour ${_current?.group ?? 'la source'}'));
      }
    });
  }

  // -------------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------------

  Map<String, String> get _headers {
    final v = _current;
    if (v == null) return const {};
    final configured = _app.sourceOf(v)?.imageHeaders ?? const <String, String>{};
    if (v.sourceId == 'sushiscan_net') {
      // Le referent est la fiche precise du chapitre, pas la page d'accueil.
      return {...configured, ..._routeHeaders, 'Referer': v.chapterId};
    }
    return {...configured, ..._routeHeaders};
  }

  double get _contentWidth {
    final screen = MediaQuery.sizeOf(context).width;
    if (_mode != ReaderMode.vertical) return screen;
    return math.min(screen, _app.settings.verticalMaxWidth);
  }

  ImageProvider _provider(int i) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = (_contentWidth * dpr).round().clamp(320, 2000);
    final local = _localPages;
    // Very tall webtoon strips (30 000 px) exceed the GPU texture limit
    // (16 384 px) and can blank the whole window on Windows: the decoded
    // size is capped on both axes, without ever enlarging an image.
    ImageProvider capped(ImageProvider base) => ResizeImage(base, width: w, height: 16000,
        policy: ResizeImagePolicy.fit);
    if (local != null) return capped(MemoryImage(local[i]));
    final p = _pages![i];
    final url = (_useFallback.contains(i) && p.fallbackUrl != null) ? p.fallbackUrl! : p.url;
    return capped(NetworkImage(url, headers: _headers));
  }

  void _precacheAround(int center) {
    final pages = _pages;
    if (pages == null || pages.isEmpty || !mounted) return;
    for (var i = center + 1; i <= center + 4 && i < pages.length; i++) {
      precacheImage(_provider(i), context, onError: (_, __) {});
    }
    if (center - 1 >= 0) {
      precacheImage(_provider(center - 1), context, onError: (_, __) {});
    }
  }

  Widget _image(int i, {required BoxFit fit, double? placeholderHeight}) {
    return Image(
      image: _provider(i),
      fit: fit,
      width: fit == BoxFit.fitWidth ? double.infinity : null,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, sync) {
        if (sync || frame != null) {
          final chapterId = _current?.chapterId;
          if (chapterId != null) _onDecodedImage(i, chapterId);
          return child;
        }
        return SizedBox(
          height: placeholderHeight,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: context.pal.bright)),
              const SizedBox(height: 10),
              Text('Page ${i + 1}…', style: TextStyle(color: context.pal.text.withValues(alpha: 0.8),
                  fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        final chapterId = _current?.chapterId;
        if (chapterId != null) _onBrokenImage(i, chapterId);
        return SizedBox(
        height: placeholderHeight ?? 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: context.pal.muted),
              const SizedBox(height: 8),
              Text('Page ${i + 1} indisponible',
                style: TextStyle(color: context.pal.muted)),
              // Trying the exact same unavailable URL forever is not useful.
              if (_pages != null && i < _pages!.length &&
                  _pages![i].fallbackUrl != null && !_useFallback.contains(i))
                TextButton(
                  onPressed: () => setState(() => _useFallback.add(i)),
                  child: const Text('Essayer en qualité réduite'),
                )
              else if (_otherWorkingVariant() != null)
                TextButton.icon(
                  onPressed: () => _switchVariant(_otherWorkingVariant()!, keepPage: false),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Essayer un autre lecteur'),
                )
              else
                Text('Aucun autre lecteur natif disponible pour ce chapitre.',
                  style: TextStyle(color: context.pal.muted, fontSize: 12)),
              if (_current != null && _browserAllowed(_current!))
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _siteReader = true;
                      _siteBridge = null;
                      _siteProbeBusy = false;
                      _sitePagesFound = 0;
                      _sitePagesExpected = null;
                    });
                    _armSiteStartupTimeout();
                  },
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('Réanalyser les images du chapitre'),
                ),
            ],
          ),
        ),
      );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Progression
  // -------------------------------------------------------------------------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  void _flushSave({bool deferred = false}) {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow(deferred: deferred);
    }
  }

  /// [deferred] : pendant dispose(), l'arbre de widgets est verrouillé ;
  /// on enregistre juste après, dans une micro-tâche.
  void _saveNow({bool deferred = false}) {
    final v = _current;
    final pages = _pages;
    if (v == null || pages == null || pages.isEmpty || !_decodedPages.contains(_page)) return;
    final app = _app;
    final work = widget.work;
    final key = _group.key;
    final page = _page;
    final count = pages.length;
    void save() => app.recordProgress(
          work: work,
          key: key,
          page: page,
          pageCount: count,
          variant: v,
        );
    if (deferred) {
      scheduleMicrotask(save);
    } else if (mounted) {
      save();
    }
  }

  void _setPage(int p) {
    if (p == _page) return;
    setState(() => _page = p);
    _scheduleSave();
    _precacheAround(p);
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  bool get _hasNext => _index + 1 < _groups.length;
  bool get _hasPrev => _index > 0;

  void _nextChapter() {
    if (!_hasNext) return;
    _flushSave();
    _app.setRead(widget.work, [_group.key], true);
    _openChapter(_index + 1);
  }

  void _prevChapter() {
    if (!_hasPrev) return;
    _openChapter(_index - 1);
  }

  Duration get _anim => PazuluMotion.of(context, const Duration(milliseconds: 200));

  void _nextPage() {
    final n = _pages?.length ?? 0;
    if (_mode == ReaderMode.vertical) {
      _scrollBy(0.85);
      return;
    }
    if (_page + _step < n) {
      _goToPage(_page + _step);
    } else {
      _nextChapter();
    }
  }

  void _prevPage() {
    if (_mode == ReaderMode.vertical) {
      _scrollBy(-0.85);
      return;
    }
    if (_page > 0) _goToPage(_page - _step);
  }

  void _goToPage(int p) {
    final n = _pages?.length ?? 0;
    if (n == 0) return;
    final target = p.clamp(0, n - 1);
    if (_mode == ReaderMode.vertical) {
      _scrollToPage(target);
      _setPage(target);
    } else {
      final pager = _pager;
      if (pager != null && pager.hasClients) {
        final index = _pagerIndexFor(target);
        if (_anim == Duration.zero || (target - _page).abs() > _step) {
          pager.jumpToPage(index);
        } else {
          pager.animateToPage(index, duration: _anim, curve: PazuluMotion.curve);
        }
      }
    }
  }

  void _scrollBy(double viewports) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (pos.pixels + pos.viewportDimension * viewports)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (_anim == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: _anim, curve: PazuluMotion.curve);
    }
  }

  /// Fait défiler jusqu'à une page (les pages hors écran ne sont pas
  /// construites : on avance par bonds jusqu'à ce qu'elle existe).
  Future<void> _scrollToPage(int target) async {
    if (!_scroll.hasClients || target < 0 || target >= _keys.length) return;
    if (target < _page) _scroll.jumpTo(0);
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = _keys[target].currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.0);
        return;
      }
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) return;
      _scroll.jumpTo(math.min(pos.maxScrollExtent, pos.pixels + pos.viewportDimension * 1.5));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Détermine la page affichée en mode vertical.
  void _probeVisiblePage() {
    if (_probeScheduled) return;
    _probeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeScheduled = false;
      if (!mounted || _keys.isEmpty) return;
      final probeY = MediaQuery.sizeOf(context).height * 0.35;
      int? best;
      for (var i = 0; i < _keys.length; i++) {
        final ctx = _keys[i].currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (top <= probeY) {
          best = i;
        } else {
          break;
        }
      }
      final b = best;
      if (b != null) _setPage(b);
    });
  }

  void _toggleUi() {
    if (_current?.isExternal ?? false) return;
    _hideTimer?.cancel();
    setState(() => _uiVisible = !_uiVisible);
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(
        _uiVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
    }
  }

  void _cycleMode() =>
      _setMode(ReaderMode.values[(_mode.index + 1) % ReaderMode.values.length]);

  void _setMode(ReaderMode next, {bool announce = true}) {
    if (next == _mode) return;
    final page = _page;
    _pager?.dispose();
    setState(() {
      _mode = next;
      _pager = PageController(initialPage: _pagerIndexFor(page));
    });
    // The automatic direction stays editable and is remembered per work.
    _app.setReaderModeOverride(widget.work, next);
    if (next == ReaderMode.vertical && page > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPage(page));
    }
    if (announce) _flash('Mode : ${next.label} (mémorisé pour cette œuvre)');
  }

  void _toggleDoublePage() => _setDoublePage(!_doublePage);

  void _setDoublePage(bool value, {bool announce = true}) {
    if (value == _doublePage) return;
    final page = _page;
    _pager?.dispose();
    setState(() {
      _doublePage = value;
      _pager = PageController(initialPage: _pagerIndexFor(page));
    });
    _app.updateSettings((s) => s.doublePage = _doublePage);
    if (announce) _flash(_doublePage ? 'Double page' : 'Page unique');
  }

  void _cycleFit() => _setFit(PageFit.values[(_fit.index + 1) % PageFit.values.length]);

  void _setFit(PageFit next, {bool announce = true}) {
    if (next == _fit) return;
    setState(() => _fit = next);
    _app.updateSettings((s) => s.pageFit = next);
    if (announce) _flash('Ajustement : ${next.label}');
  }

  void _flash(String message) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
  }

  /// Reading background: pure black (OLED), graphite or paper-dark.
  static const _backgrounds = [Color(0xFF000000), Color(0xFF15151C), Color(0xFF26231E)];
  int _background = 0;

  Future<void> _openReaderSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, refresh) {
        final p = sheetContext.pal;
        void apply(VoidCallback f) {
          f();
          refresh(() {});
        }
        Widget label(String t) => Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(t, style: TextStyle(color: p.muted, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Réglages de lecture', style: Theme.of(sheetContext).textTheme.titleLarge),
                label('SENS DE LECTURE  ·  M'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReaderMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ReaderMode.vertical,
                          icon: Icon(Icons.view_day_outlined), label: Text('Vertical')),
                      ButtonSegment(value: ReaderMode.ltr,
                          icon: Icon(Icons.east_rounded), label: Text('G → D')),
                      ButtonSegment(value: ReaderMode.rtl,
                          icon: Icon(Icons.west_rounded), label: Text('D → G')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => apply(() => _setMode(v.first, announce: false)),
                  ),
                ),
                if (_mode == ReaderMode.vertical) ...[
                  label('LARGEUR DU WEBTOON  ·  ${_app.settings.verticalMaxWidth.round()} px'),
                  Slider(
                    value: _app.settings.verticalMaxWidth.clamp(480, 1800).toDouble(),
                    min: 480,
                    max: 1800,
                    divisions: 33,
                    label: '${_app.settings.verticalMaxWidth.round()} px',
                    onChanged: (v) => apply(() {
                      _app.updateSettings((s) => s.verticalMaxWidth = v);
                      setState(() {});
                    }),
                  ),
                ] else ...[
                  label('AJUSTEMENT  ·  W'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PageFit>(
                      showSelectedIcon: false,
                      segments: [
                        for (final f in PageFit.values)
                          ButtonSegment(value: f, label: Text(f.label)),
                      ],
                      selected: {_fit},
                      onSelectionChanged: (v) => apply(() => _setFit(v.first, announce: false)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Double page  ·  D'),
                    subtitle: const Text('Deux pages côte à côte, ordre japonais en D → G'),
                    value: _doublePage,
                    onChanged: (v) => apply(() => _setDoublePage(v, announce: false)),
                  ),
                ],
                label('FOND'),
                Row(children: [
                  for (var i = 0; i < _backgrounds.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Semantics(
                        button: true,
                        selected: _background == i,
                        label: const ['Noir', 'Graphite', 'Sépia sombre'][i],
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => apply(() => setState(() => _background = i)),
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: _backgrounds[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _background == i ? p.bright : p.borderStrong,
                                width: _background == i ? 2.5 : 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Raccourcis : ← → pages · P / N chapitres · M mode · W ajustement · '
                    'D double page · Échap quitter',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _openChapterList() async {
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        final p = sheetContext.pal;
        final height = MediaQuery.sizeOf(sheetContext).height * 0.7;
        final readKeys = _app.entry(widget.work.id)?.progress.readKeys ?? const <String>{};
        return SizedBox(
          height: height,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(children: [
                Text('Chapitres', style: Theme.of(sheetContext).textTheme.titleLarge),
                const Spacer(),
                Text('${_groups.length}', style: TextStyle(color: p.muted)),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                // Opens around the current chapter.
                controller: ScrollController(
                    initialScrollOffset: math.max(0, _index - 4) * 52.0),
                itemExtent: 52,
                itemCount: _groups.length,
                itemBuilder: (_, i) {
                  final g = _groups[i];
                  final current = i == _index;
                  final read = readKeys.contains(g.key.id);
                  return ListTile(
                    selected: current,
                    selectedTileColor: p.selected,
                    leading: SizedBox(width: 56, child: Text(
                        g.key.number != null ? g.key.id : '•',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            color: read && !current ? p.muted : p.text))),
                    title: Text(g.title ?? g.key.longLabel, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: read && !current ? p.muted : p.text)),
                    trailing: current
                        ? Icon(Icons.play_arrow_rounded, color: p.bright)
                        : (read ? Icon(Icons.check_rounded, size: 18, color: p.muted) : null),
                    onTap: () => Navigator.of(sheetContext).pop(i),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
    if (target != null && target != _index && mounted) {
      _flushSave();
      _openChapter(target);
    }
  }


  // -------------------------------------------------------------------------
  // Clavier (Windows)
  // -------------------------------------------------------------------------

  static final _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final rtl = _mode == ReaderMode.rtl;

    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleUi();
    } else if (k == LogicalKeyboardKey.keyN) {
      _nextChapter();
    } else if (k == LogicalKeyboardKey.keyP) {
      _prevChapter();
    } else if (k == LogicalKeyboardKey.keyM) {
      _cycleMode();
    } else if (k == LogicalKeyboardKey.keyD) {
      _toggleDoublePage();
    } else if (k == LogicalKeyboardKey.keyW) {
      _cycleFit();
    } else if (k == LogicalKeyboardKey.keyC) {
      _openChapterList();
    } else if (k == LogicalKeyboardKey.keyL) {
      _openReaderSheet();
    } else if (k == LogicalKeyboardKey.keyS) {
      _openReaderSettings();
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.arrowDown) {
      _nextPage();
    } else if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.arrowUp) {
      _prevPage();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      rtl ? _prevPage() : _nextPage();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      rtl ? _nextPage() : _prevPage();
    } else if (k == LogicalKeyboardKey.home) {
      _goToPage(0);
    } else if (k == LogicalKeyboardKey.end) {
      _goToPage((_pages?.length ?? 1) - 1);
    } else {
      final digit = _digitKeys.indexOf(k);
      if (digit < 0) return KeyEventResult.ignored;
      _switchVariant(digit);
    }
    return KeyEventResult.handled;
  }

  // Never leave a blank spinner indefinitely when WebView2 could not
  // initialize (for example after a native crash guard entered safe mode).
  void _armSiteStartupTimeout() {
    _siteStartupTimer?.cancel();
    _siteStartupTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_siteReader || _siteProbeBusy) return;
      AppLog.error('Delai depasse avant initialisation WebView2',
          _current?.chapterId ?? 'chapitre absent');
      _routeAfterFailure(StateError('WebView2 ne repond pas apres 25 secondes.'));
    });
  }

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------

  // La WebView2 reste CACHEE. Elle ne sert qu'a executer le JavaScript
  // de la page, puis a transmettre les URLs presentes dans le DOM au lecteur
  // Flutter existant. Aucun site tiers ne devient notre interface.
  Future<void> _captureRenderedPages(EmbeddedBrowserBridge bridge) async {
    if (_siteProbeBusy || !_siteReader) return;
    final chapter = _current;
    if (chapter == null) return;
    final expectedChapter = chapter.chapterId;
    final generation = ++_siteCaptureGeneration;
    _siteStartupTimer?.cancel();
    setState(() => _siteProbeBusy = true);

    bool active() => mounted && _siteReader &&
        generation == _siteCaptureGeneration &&
        _current?.chapterId == expectedChapter;

    Future<ChapterPagination> inspect({int? requested,
        Set<String>? previousImages}) async {
      Object? lastError;
      ChapterPagination? last;
      var stable = 0;
      for (var attempt = 0; attempt < 32; attempt++) {
        if (!active()) throw StateError('Analyse interrompue.');
        try {
          final result = await bridge.run(visiblePagesScript);
          final snapshot = ChapterPagination.fromBrowser(result,
              chapterUrl: expectedChapter);
          final currentImages = snapshot.pages.map((page) => page.url).toSet();
          final matchesPage = requested == null || snapshot.current == requested;
          final hasChanged = previousImages == null ||
              currentImages.difference(previousImages).isNotEmpty;
          if (matchesPage && hasChanged) {
            if (last != null &&
                last.pages.map((p) => p.url).join('|') ==
                    snapshot.pages.map((p) => p.url).join('|')) {
              stable++;
            } else {
              stable = 0;
            }
            last = snapshot;
            if (stable >= 1) return snapshot;
          }
        } catch (error) {
          lastError = error;
        }
        if (attempt < 31) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
      throw StateError('Impossible de confirmer la page '
          '${requested ?? 1} du chapitre. Dernier diagnostic : $lastError');
    }

    try {
      // 1. Is this rendered page a chapter at all, or a paywall / login /
      //    age gate / challenge? Detection only: nothing is clicked.
      await _checkRenderedAccess(bridge, active);
      if (!active()) return;
      final first = await inspect();
      if (!active()) return;
      final total = first.total;
      List<PageRef> pages;
      if (!first.isIncomplete) {
        pages = first.pages;
      } else {
        final selector = first.selectIndex;
        if (selector == null || total == null) {
          throw StateError('La source annonce $total pages mais ne fournit '
              'pas de selecteur de navigation accessible.');
        }
        final collected = <int, PageRef>{};
        var previousImages = first.pages.map((p) => p.url).toSet();
        if (first.current >= 1 && first.current <= total &&
            first.pages.length == 1) {
          collected[first.current] = first.pages.single;
        }
        setState(() {
          _sitePagesFound = collected.length;
          _sitePagesExpected = total;
        });
        for (var target = 1; target <= total; target++) {
          if (!active()) return;
          if (collected.containsKey(target)) continue;
          bool accepted;
          try {
            final result = await bridge.run(
                browserTurnToPageScript(target, selector));
            accepted = browserTurnAccepted(result);
          } catch (error) {
            // Some WebView2 implementations reject a JS promise when the
            // ordinary page selector starts a full document navigation.
            // Verify the destination DOM instead of assuming success.
            AppLog.info('Navigation pendant le changement de page : $error');
            accepted = true;
          }
          if (!accepted) {
            throw StateError('Le selecteur du site refuse la page $target/$total.');
          }
          final snapshot = await inspect(requested: target,
              previousImages: previousImages);
          if (snapshot.pages.length != 1) {
            throw StateError('La page $target/$total fournit '
                '${snapshot.pages.length} images ; ordre incertain.');
          }
          collected[target] = snapshot.pages.single;
          previousImages = snapshot.pages.map((p) => p.url).toSet();
          if (!active()) return;
          setState(() => _sitePagesFound = collected.length);
        }
        pages = [for (var index = 1; index <= total; index++)
          if (collected[index] != null) collected[index]!];
        if (pages.length != total ||
            pages.map((p) => p.url).toSet().length != total) {
          throw StateError('Le chapitre reste incomplet : '
              '${pages.length}/$total pages distinctes.');
        }
      }
      if (!active()) return;
      ReaderFailover.validatePages(chapter, pages);
      // 2. Same Page Validation Engine as API/HTML readers: real images,
      //    announced total, no spinner/logo/HTML disguised as a page.
      final verdict = await _app.engine.chapterResolver.validate(
        PageFetch(pages: pages, announcedTotal: total, transport: 'browser',
            imageHeaders: {'Referer': chapter.chapterId}),
        chapter: chapter,
        extraHeaders: _headers,
      );
      if (!active()) return;
      if (!verdict.readable) {
        throw ChapterValidationException(verdict.summary, result: verdict);
      }
      _app.recordValidatedRead(chapter, verdict);
      // Le HWND natif reste cache avant de rendre les images dans Flutter.
      await bridge.setVisible(false);
      if (!active()) return;
      _pager?.dispose();
      final start = _startPage.clamp(0, pages.length - 1);
      setState(() {
        _siteReader = false;
        _siteBridge = null;
        _pages = pages;
        _localPages = null;
        _page = start;
        _error = null;
        _loading = false;
        _keys = List.generate(pages.length, (_) => GlobalKey());
        _pager = PageController(initialPage: _pagerIndexFor(start));
      });
      _app.reportChapterSuccess(chapter);
      _verifiedVariants.add(_variant);
      _rememberManualChoice(chapter);
      _brokenImagesHandled.clear();
      _decodedPages.clear();
      _precacheAround(start);
    } catch (error, stack) {
      AppLog.error('Extraction automatique du chapitre pagine', error, stack);
      try { await bridge.setVisible(false); } catch (_) {}
      if (!active()) return;
      _routeAfterFailure(error is ChapterRestrictedException
          ? error
          : StateError('Chapitre non chargé intégralement : $error'));
    } finally {
      if (mounted && generation == _siteCaptureGeneration) {
        setState(() => _siteProbeBusy = false);
      }
    }
  }

  Future<void> _checkRenderedAccess(EmbeddedBrowserBridge bridge,
      bool Function() active) async {
    // The DOM may still be loading: sample a few times, briefly.
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!active()) return;
      try {
        Object? value = await bridge.run(accessProbeScript);
        for (var i = 0; i < 3 && value is String; i++) {
          value = jsonDecode(value);
        }
        if (value is Map) {
          final text = '${value['title'] ?? ''} ${value['text'] ?? ''}';
          final images = value['images'] is int ? value['images'] as int : 0;
          final kind = AccessDetector.classifyText(text, imageCount: images);
          // A cookie bar over a chapter still loading is not a verdict.
          if (kind.isRestriction && kind != AccessKind.cookieConsent) {
            throw ChapterRestrictedException('Page rendue : ${kind.label}. '
                'Aucun contournement n\'est tenté.', kind: kind);
          }
          if (text.trim().length > 40) return;
        }
      } on ChapterRestrictedException {
        rethrow;
      } catch (_) {
        // Script refused while the document navigates: sample again.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Widget _embeddedSiteReader() {
    final chapter = _current;
    final uri = chapter == null ? null : safeReadingUri(chapter.chapterId);
    if (chapter == null || uri == null || uri.hasPort || uri.userInfo.isNotEmpty ||
        !_browserAllowed(chapter)) {
      return const Center(child: Text('Adresse de chapitre non autorisée.'));
    }
    // Les commandes restent Flutter. Le navigateur est TOUJOURS invisible
    // (setVisibility(false) AVANT loadRequest), meme pendant le chargement.
    return SafeArea(child: Column(children: [
      Container(
        color: const Color(0xFF101126),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          IconButton(
            tooltip: 'Retour a la fiche',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.work.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_group.key.longLabel} · Moteur Pazulu',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.pal.muted, fontSize: 12)),
            ],
          )),
        ]),
      ),
      _readerSwitcher(),
      Expanded(child: Stack(children: [
        // The hidden WebView2 is a native window ABOVE Flutter on Windows:
        // even hidden it gets a 1×1 px box, so it can never cover the screen
        // (black screen on some chapters). Pages are read from the DOM
        // attributes (src, data-src…), the viewport size does not matter.
        Positioned(left: 0, top: 0, width: 1, height: 1, child: OfficialWebView(
          key: ValueKey('pazulu-hidden-${chapter.chapterId}'),
          url: chapter.chapterId,
          initiallyVisible: false,
          onScriptRunner: (bridge) {
            if (!mounted || !_siteReader) return;
            _siteBridge = bridge;
            if (bridge != null && !_siteProbeBusy) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _siteReader) {
                  unawaited(_captureRenderedPages(bridge));
                }
              });
            }
          },
          fallback: const SizedBox.shrink(),
        )),
        // La WebView native est cachee, cette interface Flutter est la seule
        // surface visible. Aucun header/menu de SushiScan n'est affiche.
        Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: context.pal.bright),
            const SizedBox(height: 20),
            Text(_sitePagesExpected == null
                ? 'Analyse des pages du chapitre...'
                : 'Chargement : $_sitePagesFound/$_sitePagesExpected pages',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Preparation dans le moteur Pazulu, sans afficher le site.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.pal.muted)),
          ]),
        )),
      ])),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_siteReader) {
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(backgroundColor: context.pal.background, body: _embeddedSiteReader()),
      );
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: _backgrounds[_background],
        body: Stack(
          children: [
            Positioned.fill(child: _body()),
            _progressLine(),
            _topBar(),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: ListenableBuilder(
          listenable: _app,
          builder: (context, _) {
            final v = _current;
            final progress = v == null ? null : _app.downloading[v.chapterId];
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(value: progress),
                  const SizedBox(height: PazuluSpace.md),
                  Text(
                    progress == null
                        ? 'Recherche du ${_group.key.longLabel.toLowerCase()}…'
                        : 'Telechargement automatique · ${(progress * 100).round()} %',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.pal.muted),
                  ),
                  if (_routeSteps.isNotEmpty) ...[
                    const SizedBox(height: PazuluSpace.md),
                    _routeStepList(maxLines: 5),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }
    final v = _current;
    if (v != null && v.isExternal) return _externalBody(v);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PazuluSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: context.pal.muted),
              const SizedBox(height: PazuluSpace.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text('$_error', textAlign: TextAlign.center),
              ),
              if (_routeSteps.isNotEmpty) ...[
                const SizedBox(height: PazuluSpace.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _routeStepList(maxLines: 8),
                ),
              ],
              const SizedBox(height: PazuluSpace.md),
              Wrap(
                spacing: PazuluSpace.sm,
                runSpacing: PazuluSpace.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      _app.resumePausedSources();
                      _failedVariants.clear();
                      _loadPages();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _searchingAlternatives ? null : _searchAlternatives,
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('Rechercher une autre source'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final pages = _pages ?? const <PageRef>[];
    if (pages.isEmpty) {
      return const Center(child: Text('Ce chapitre ne contient aucune page.'));
    }
    return _mode == ReaderMode.vertical ? _verticalReader(pages) : _pagedReader(pages);
  }

  Widget _verticalReader(List<PageRef> pages) {
    final screenH = MediaQuery.sizeOf(context).height;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification || n is ScrollEndNotification) _probeVisiblePage();
        return false;
      },
      child: GestureDetector(
        onTap: _toggleUi,
        child: ListView.builder(
          key: ValueKey('v-$_index-$_variant'),
          controller: _scroll,
          cacheExtent: screenH * 2,
          // The first page starts below the top panel and the last one
          // above the bottom bar: nothing is hidden behind the controls.
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 84, bottom: 96),
          itemCount: pages.length + 1,
          itemBuilder: (context, i) {
            if (i == pages.length) return _chapterEnd();
            return Center(
              key: _keys[i],
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _contentWidth),
                child: _image(i, fit: BoxFit.fitWidth, placeholderHeight: screenH * 0.8),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pagedReader(List<PageRef> pages) {
    final rtl = _mode == ReaderMode.rtl;
    final spread = _spread;
    final count = spread ? (pages.length + 1) ~/ 2 : pages.length;
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final x = d.localPosition.dx / c.maxWidth;
          if (x < 0.3) {
            rtl ? _nextPage() : _prevPage();
          } else if (x > 0.7) {
            rtl ? _prevPage() : _nextPage();
          } else {
            _toggleUi();
          }
        },
        child: PageView.builder(
          key: ValueKey('p-$_index-$_variant-${_mode.name}-$spread'),
          controller: _pager,
          reverse: rtl,
          itemCount: count,
          onPageChanged: (i) => _setPage(spread ? i * 2 : i),
          itemBuilder: (context, i) {
            if (!spread) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: _fitted(i, c),
              );
            }
            final first = i * 2;
            final second = first + 1 < pages.length ? first + 1 : null;
            // Japanese order: the first page of a spread sits on the RIGHT.
            final children = <Widget>[
              Expanded(child: _image(first, fit: BoxFit.contain)),
              if (second != null) Expanded(child: _image(second, fit: BoxFit.contain)),
            ];
            return InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Row(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                children: children,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fitted(int i, BoxConstraints c) => switch (_fit) {
        PageFit.contain => Center(child: _image(i, fit: BoxFit.contain)),
        // Width: the page can be taller than the screen and scrolls.
        PageFit.width => SingleChildScrollView(
            child: SizedBox(width: c.maxWidth,
                child: _image(i, fit: BoxFit.fitWidth))),
        PageFit.height => Center(
            child: SizedBox(height: c.maxHeight,
                child: _image(i, fit: BoxFit.fitHeight))),
      };

  Widget _chapterEnd() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: PazuluSpace.lg),
      child: Column(
        children: [
          Text('Fin du ${_group.key.longLabel.toLowerCase()}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: PazuluSpace.md),
          if (_hasNext)
            GlowButton(
              onPressed: _nextChapter,
              icon: Icons.skip_next_rounded,
              label: _groups[_index + 1].key.longLabel,
              big: true,
            )
          else
            Text(
              'Dernier chapitre disponible. Pazulu vous préviendra des prochaines sorties.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.pal.muted),
            ),
        ],
      ),
    );
  }

  /// Metadata-only publisher link. It must never appear as a fake 1/1 image
  /// chapter, nor silently mark the user's progress as completed.
  Widget _externalBody(SourceChapter v) {
    final p = context.pal;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(PazuluSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_off_rounded, size: 44, color: p.bright),
            const SizedBox(height: PazuluSpace.md),
            Text('Chapitre reference chez ${v.group}',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
            const SizedBox(height: PazuluSpace.sm),
            Text('Le catalogue fournit uniquement un lien, pas les images du '
              'chapitre. Le site peut demander un abonnement ou renvoyer 404. '
              'Ce n est pas une lecture hors ligne.',
              style: TextStyle(color: p.muted), textAlign: TextAlign.center),
            const SizedBox(height: PazuluSpace.lg),
            FilledButton.icon(
              onPressed: () {
                final uri = Uri.tryParse(v.externalUrl!);
                if (uri == null || uri.scheme != 'https' ||
                    uri.host.isEmpty || uri.userInfo.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Lien externe invalide ou non securise.'),
                  ));
                  return;
                }
                pushPage(context, SourceBrowserPage(
                  title: '${widget.work.title} · ${_group.key.label}',
                  url: v.externalUrl!,
                ));
              },
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Consulter le lien dans Pazulu'),
            ),
            if (_variants.any((c) => !c.isExternal)) ...[
              const SizedBox(height: PazuluSpace.sm),
              TextButton.icon(
                onPressed: () {
                  final next = _variants.indexWhere((c) => !c.isExternal);
                  if (next >= 0) _switchVariant(next, keepPage: false);
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Lire une version native'),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _externalActions(SourceChapter v) {
    return TextButton.icon(
      onPressed: () {
        _app.setRead(widget.work, [_group.key], true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chapitre marque comme lu')),
        );
      },
      icon: const Icon(Icons.done_rounded),
      label: const Text('Marquer comme lu'),
    );
  }

  /// Hairline progress through the chapter, visible while reading (UI hidden).
  Widget _progressLine() {
    final n = _pages?.length ?? 0;
    if (n == 0) return const SizedBox.shrink();
    final p = context.pal;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _uiVisible ? 0 : 1,
          duration: PazuluMotion.of(context, PazuluMotion.exit),
          child: LinearProgressIndicator(
            value: ((_page + 1) / n).clamp(0, 1).toDouble(),
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: p.bright.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  /// Floating translucent panel used by the reader chrome.
  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(6)}) {
    final p = context.pal;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(PazuluRadius.big),
        border: Border.all(color: p.borderStrong),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }

  Widget _chromeButton({required String tooltip, required IconData icon,
      required VoidCallback? onPressed, bool active = false}) {
    final p = context.pal;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: active ? p.selected : null,
        foregroundColor: active ? p.bright : p.text,
        disabledForegroundColor: p.muted.withValues(alpha: 0.4),
      ),
      icon: Icon(icon, size: 22),
    );
  }

  Widget _topBar() {
    final pages = _pages?.length ?? 0;
    final v = _current;
    final p = context.pal;
    final source = v == null
        ? null
        : v.isExternal
            ? 'site officiel · ${v.group}'
            : _localPages != null ? 'hors ligne · ${v.group}' : _sourceLabel(v);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_uiVisible,
        child: AnimatedSlide(
          offset: _uiVisible ? Offset.zero : const Offset(0, -0.4),
          duration: PazuluMotion.of(context, PazuluMotion.exit),
          curve: PazuluMotion.curve,
          child: AnimatedOpacity(
            opacity: _uiVisible ? 1 : 0,
            duration: PazuluMotion.of(context, PazuluMotion.exit),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _panel(
                      child: Row(
                        children: [
                          _chromeButton(tooltip: 'Retour (Échap)', icon: Icons.arrow_back_rounded,
                              onPressed: () => Navigator.of(context).maybePop()),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(widget.work.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                                Text(
                                  [
                                    _group.key.longLabel,
                                    if (pages > 0) 'page ${_page + 1}/$pages',
                                    if (source != null) source,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: p.muted),
                                ),
                              ],
                            ),
                          ),
                          _sourceButton(),
                          const SizedBox(width: 4),
                          _chromeButton(tooltip: 'Chapitres (C)', icon: Icons.format_list_numbered_rounded,
                              onPressed: _openChapterList),
                          if (_mode != ReaderMode.vertical)
                            _chromeButton(
                              tooltip: _doublePage ? 'Page unique (D)' : 'Double page (D)',
                              icon: Icons.auto_stories_rounded,
                              active: _doublePage,
                              onPressed: _toggleDoublePage,
                            ),
                          _chromeButton(
                            tooltip: 'Mode : ${_mode.label} (M)',
                            icon: switch (_mode) {
                              ReaderMode.vertical => Icons.view_day_outlined,
                              ReaderMode.ltr => Icons.east_rounded,
                              ReaderMode.rtl => Icons.west_rounded,
                            },
                            onPressed: _cycleMode,
                          ),
                          _chromeButton(tooltip: 'Réglages de lecture (S)', icon: Icons.tune_rounded,
                              onPressed: _openReaderSettings),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Which reader is used, on a solid button: the list of readers opens
  /// in a panel instead of floating over the page being read.
  Widget _sourceButton() {
    final p = context.pal;
    final v = _current;
    final failed = _failedVariants.length;
    return Tooltip(
      message: 'Changer de lecteur (L)',
      child: TextButton.icon(
        onPressed: _variants.isEmpty ? null : _openReaderSheet,
        style: TextButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.surfaceHigh,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(Icons.swap_horiz_rounded, size: 18,
            color: failed > 0 ? p.warning : p.bright),
        label: Text(v == null
            ? 'Lecteurs'
            : 'Lecteur ${_variant + 1}/${_variants.length} · ${v.lang.toUpperCase()}'),
      ),
    );
  }

  /// Every reader of the chapter, grouped by language, all visible (no
  /// horizontal scrolling); the language is chosen with one click.
  Future<void> _openReaderSheet() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 1000),
      builder: (sheet) {
        final p = sheet.pal;
        void close() => Navigator.of(sheet).pop();
        final options = [for (var i = 0; i < _variants.length; i++) _optionFor(i)];
        final langs = <String>[
          for (final l in _app.settings.comicLangs)
            if (options.any((o) => o.lang == l)) l,
          for (final o in options)
            if (!_app.settings.comicLangs.contains(o.lang)) o.lang,
        ].toSet().toList();
        final currentLang = _current?.lang;

        Widget tile(ReaderOption o) {
          final selected = o.index == _variant;
          final (IconData icon, Color color, String state) = switch (o.status) {
            ReaderOptionStatus.verified => (Icons.verified_rounded, p.success, 'Vérifié'),
            ReaderOptionStatus.offline => (Icons.download_done_rounded, p.bright, 'Hors ligne'),
            ReaderOptionStatus.failed => (Icons.error_outline_rounded, p.danger, 'Échec'),
            ReaderOptionStatus.external => (Icons.open_in_new_rounded, p.muted, 'Lien éditeur'),
            ReaderOptionStatus.needsConfirmation => (Icons.help_rounded, p.warning, 'À confirmer'),
            ReaderOptionStatus.unverified => (Icons.radio_button_unchecked_rounded, p.muted, 'Non testé'),
          };
          return SizedBox(
            width: 290,
            child: Material(
              color: selected ? p.selected : p.card,
              borderRadius: BorderRadius.circular(PazuluRadius.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(PazuluRadius.card),
                onTap: () {
                  close();
                  if (o.status == ReaderOptionStatus.needsConfirmation) {
                    _confirmCandidate(o.index);
                  } else if (o.index != _variant) {
                    _switchVariant(o.index);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PazuluRadius.card),
                    border: Border.all(color: selected ? p.bright : p.border, width: selected ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Lecteur ${o.index + 1} · ${o.sourceName}', maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text([state, if (o.group != null && o.group != o.sourceName) o.group!].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ])),
                    if (selected) Icon(Icons.play_arrow_rounded, color: p.bright),
                  ]),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Lecteurs de ce chapitre · ${options.length}',
                      style: Theme.of(sheet).textTheme.titleLarge)),
                  TextButton.icon(
                    onPressed: () {
                      close();
                      _searchAlternatives();
                    },
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('Chercher d\'autres sources'),
                  ),
                ]),
                const SizedBox(height: 12),
                // Language first, in one click.
                if (langs.length > 1) ...[
                  Text('LANGUE', style: TextStyle(color: p.muted, fontSize: 12,
                      fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final l in langs)
                        ButtonSegment(value: l, label: Text(
                            '${l.toUpperCase()} · ${options.where((o) => o.lang == l).length}')),
                    ],
                    selected: {currentLang ?? langs.first},
                    onSelectionChanged: (v) {
                      close();
                      _switchLanguage(v.first);
                    },
                  ),
                  const SizedBox(height: 18),
                ],
                for (final l in langs) ...[
                  Text(l == 'fr' ? 'FRANÇAIS' : (l == 'en' ? 'ANGLAIS' : l.toUpperCase()),
                      style: TextStyle(color: p.bright, fontSize: 12,
                          fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final o in options.where((o) => o.lang == l)) tile(o),
                  ]),
                  const SizedBox(height: 18),
                ],
                if (_alternativesNote != null)
                  Text(_alternativesNote!, style: TextStyle(color: p.muted, fontSize: 12)),
                TextButton.icon(
                  onPressed: () {
                    close();
                    final v = _current;
                    if (v == null) return;
                    _app.setPreferredVariant(widget.work, v, explicit: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lecteur par défaut : ${_sourceLabel(v)}')),
                    );
                  },
                  icon: const Icon(Icons.push_pin_outlined),
                  label: const Text('Garder ce lecteur par défaut pour cette œuvre'),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  /// Same chapter in another language: the best reader of that language
  /// (not failed, verified first), remembered for the work.
  void _switchLanguage(String lang) {
    if (_current?.lang == lang) return;
    int? best;
    for (var i = 0; i < _variants.length; i++) {
      final v = _variants[i];
      if (v.lang != lang || v.isExternal || _failedVariants.contains(i)) continue;
      if (best == null || _verifiedVariants.contains(i)) best = i;
      if (_verifiedVariants.contains(i)) break;
    }
    if (best == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pas de lecteur ${lang.toUpperCase()} disponible pour ce chapitre.')));
      return;
    }
    _app.setPreferredLang(widget.work, lang);
    _switchVariant(best, keepPage: false);
  }

  Widget _readerSwitcher() {
    final options = <ReaderOption>[
      for (var i = 0; i < _variants.length; i++) _optionFor(i),
    ];
    return ReaderSwitcher(
      options: options,
      selected: _variant,
      onSelect: _switchVariant,
      onConfirm: _confirmCandidate,
      searching: _searchingAlternatives,
      note: _alternativesNote,
      onSearchAlternatives: _searchAlternatives,
      onSetDefault: () {
        final v = _current;
        if (v == null) return;
        _app.setPreferredVariant(widget.work, v, explicit: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lecteur par défaut : ${_sourceLabel(v)}')),
        );
      },
    );
  }

  ReaderOption _optionFor(int i) {
    final c = _variants[i];
    final source = _app.sourceOf(c);
    final ReaderOptionStatus status;
    String? detail;
    if (c.isExternal) {
      status = ReaderOptionStatus.external;
    } else if (_app.downloadOf(c.chapterId) != null) {
      status = ReaderOptionStatus.offline;
    } else if (_failedVariants.contains(i)) {
      status = ReaderOptionStatus.failed;
      for (final step in _routeSteps.reversed) {
        if (step.index == i) {
          detail = step.message;
          break;
        }
      }
    } else if (_needsConfirmation.contains(i) && !_confirmed.contains(i)) {
      status = ReaderOptionStatus.needsConfirmation;
      detail = 'Même numéro, mais l\'édition ou le volume diffère : '
          'Pazulu ne l\'ouvre pas sans votre accord.';
    } else if (_verifiedVariants.contains(i) ||
        _app.lastKnownStatus(c.sourceId) == SourceStatus.fullReader) {
      status = ReaderOptionStatus.verified;
    } else {
      status = ReaderOptionStatus.unverified;
    }
    return ReaderOption(
      index: i,
      sourceName: source?.name ?? c.sourceId,
      lang: c.lang,
      group: c.group,
      status: status,
      detail: detail,
    );
  }

  Widget _routeStepList({int maxLines = 5}) {
    final steps = _routeSteps.length > maxLines
        ? _routeSteps.sublist(_routeSteps.length - maxLines)
        : _routeSteps;
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(switch (step.state) {
                  RouteStepState.confirmed => Icons.check_circle_rounded,
                  RouteStepState.checking => Icons.hourglass_top_rounded,
                  RouteStepState.needsBrowser => Icons.web_asset_rounded,
                  RouteStepState.restricted => Icons.lock_outline_rounded,
                  RouteStepState.skippedNeedsConfirmation => Icons.rule_rounded,
                  RouteStepState.skippedDifferentChapter ||
                  RouteStepState.skippedLanguage ||
                  RouteStepState.skippedExternal ||
                  RouteStepState.skippedNoConnector => Icons.remove_circle_outline_rounded,
                  _ => Icons.error_outline_rounded,
                }, size: 15, color: step.state == RouteStepState.confirmed
                    ? const Color(0xFF4ADE80) : p.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(step.line,
                    style: TextStyle(color: p.muted, fontSize: 12))),
              ],
            ),
          ),
      ],
    );
  }

  /// Metadata-only lookup of the same work on the other connectors, then
  /// refresh of this chapter's readers. No page is downloaded here.
  Future<void> _searchAlternatives() async {
    if (_searchingAlternatives) return;
    setState(() {
      _searchingAlternatives = true;
      _alternativesNote = 'Recherche du ${_group.key.longLabel.toLowerCase()} '
          'dans les autres sources…';
    });
    final key = _group.key;
    try {
      final (report, variants) = await _app.searchAlternativeReaders(widget.work, key);
      if (!mounted) return;
      final known = {for (final v in _variants) '${v.sourceId}|${v.chapterId}'};
      final fresh = variants.where((v) => !known.contains('${v.sourceId}|${v.chapterId}')).toList();
      setState(() {
        _searchingAlternatives = false;
        if (fresh.isEmpty) {
          _alternativesNote = report.checked == 0
              ? 'Aucun autre connecteur actif. Activez ou installez une extension '
                  '(Réglages → Moteur Pazulu → Extensions).'
              : 'Aucune autre source ne propose ce chapitre (${report.checked} '
                  'connecteur(s) consulté(s)${report.unavailable > 0 ? ', ${report.unavailable} injoignable(s)' : ''}).';
        } else {
          final current = _current;
          final groupIndex = _groups.indexWhere((g) => g.key == key);
          if (groupIndex >= 0) {
            _groups[groupIndex] = ChapterGroup(key, [..._groups[groupIndex].variants, ...fresh]);
          }
          _variants = [..._variants, ...fresh];
          if (current != null) {
            final i = _variants.indexOf(current);
            if (i >= 0) _variant = i;
          }
          _alternativesNote = '${fresh.length} nouveau(x) lecteur(s) trouvé(s).';
        }
      });
      // A failed chapter can now be retried on the new readers.
      if (fresh.isNotEmpty && _error != null) {
        unawaited(_loadPages());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchingAlternatives = false;
        _alternativesNote = 'Recherche impossible : $e';
      });
    }
  }

  Future<void> _confirmCandidate(int index) async {
    final c = _variants[index];
    final requested = _requested ?? _current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer l\'édition'),
        content: Text('Le Lecteur ${index + 1} (${_sourceLabel(c)}) propose '
            '« ${c.title ?? c.key.longLabel} »${c.volume == null ? '' : ', volume ${c.volume}'}.\n\n'
            'Vous avez demandé « ${requested?.title ?? _group.key.longLabel} »'
            '${requested?.volume == null ? '' : ', volume ${requested!.volume}'}.\n\n'
            'Pazulu n\'a pas pu prouver qu\'il s\'agit exactement du même chapitre '
            '(même édition). Ouvrir quand même ce lecteur ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true),
              child: const Text('C\'est le bon chapitre')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _confirmed.add(index));
    _switchVariant(index, keepPage: false);
  }

  String _failureText(Object failure) {
    final reason = switch (failure) {
      ChapterRestrictedException e => e.kind.label,
      ChapterValidationException e => e.result.summary,
      SourceException e => e.message,
      _ => '$failure',
    };
    final autoOff = !_app.settings.autoFailover && _variants.length > 1;
    return 'Aucun autre lecteur compatible n\'a fourni ce chapitre. '
        'Dernière raison : $reason.'
        '${autoOff ? ' (Basculement automatique désactivé dans les réglages.)' : ''}';
  }

  Widget _bottomBar() {
    final n = _pages?.length ?? 0;
    final p = context.pal;
    final rtl = _mode == ReaderMode.rtl;
    final slider = n > 1
        ? SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: p.bright,
              inactiveTrackColor: p.surfaceHigh,
              thumbColor: p.bright,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: Directionality(
              // Right-to-left manga: the slider follows the reading direction.
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Slider(
                value: _page.clamp(0, n - 1).toDouble(),
                min: 0,
                max: (n - 1).toDouble(),
                divisions: n - 1,
                label: 'Page ${_page + 1}',
                onChanged: (x) => _goToPage(x.round()),
              ),
            ),
          )
        : (_current?.isExternal ?? false)
            ? _externalActions(_current!)
            : const SizedBox.shrink();
    final next = _hasNext ? _groups[_index + 1].key.label : null;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_uiVisible,
        child: AnimatedSlide(
          offset: _uiVisible ? Offset.zero : const Offset(0, 0.4),
          duration: PazuluMotion.of(context, PazuluMotion.exit),
          curve: PazuluMotion.curve,
          child: AnimatedOpacity(
            opacity: _uiVisible ? 1 : 0,
            duration: PazuluMotion.of(context, PazuluMotion.exit),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: _panel(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          _chromeButton(tooltip: 'Chapitre précédent (P)', icon: Icons.skip_previous_rounded,
                              onPressed: _hasPrev ? _prevChapter : null),
                          if (n > 0)
                            SizedBox(
                              width: 64,
                              child: Text('${_page + 1} / $n',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: p.text, fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [FontFeature.tabularFigures()])),
                            ),
                          Expanded(child: slider),
                          if (next != null)
                            TextButton.icon(
                              onPressed: _nextChapter,
                              style: TextButton.styleFrom(minimumSize: const Size(44, 44),
                                  foregroundColor: p.bright),
                              icon: const Icon(Icons.skip_next_rounded),
                              label: Text(next),
                            )
                          else
                            _chromeButton(tooltip: 'Dernier chapitre disponible',
                                icon: Icons.skip_next_rounded, onPressed: null),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderError {
  const _ReaderError(this.message);
  final String message;
  @override
  String toString() => message;
}
