import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../engine/discovery/discovery_engine.dart';
import '../../engine/http/engine_http.dart';
import '../anime/anilist.dart';
import '../log.dart';
import '../models.dart';
import '../planning.dart';
import '../sources/mangadex.dart';
import '../sources/public_catalog.dart';
import 'mangaupdates.dart';
import 'webtoon_daily.dart';
import 'weekly_schedule.dart';

/// Builds the general weekly planning (every series, EN + FR + anime) from
/// many independent sources, so one broken site never empties it:
///
/// * AniList — every anime broadcast of the week, exact time, official
///   streaming platforms;
/// * MangaDex — every EN / FR chapter of the last weeks, exact time;
/// * MangaUpdates — releases of the last days of every series (all
///   scanlation groups), real date per chapter;
/// * WEBTOON EN and FR — official update day of each series;
/// * every directory site (Madara / MangaThemesia) — « latest updates »;
/// * the library — personal forecasts;
/// * the release history kept on disk — rhythm of each series → projection.
///
/// Metadata only: no chapter page, no video, nothing bypassed.
class ScheduleService {
  ScheduleService({
    required this.anilist,
    required this.mangadex,
    required this.http,
    required this.sites,
    required this.entries,
    required this.animeReleases,
    required this.supportDir,
    required this.notify,
  });

  final AniListClient anilist;
  final MangaDexSource mangadex;
  final EngineHttpClient http;
  final List<PublicCatalogSource> Function() sites;
  final Iterable<LibraryEntry> Function() entries;
  final List<PlannedRelease> Function() animeReleases;
  final Directory? Function() supportDir;
  final void Function() notify;

  final Map<String, SeriesHistory> _history = {};
  bool _historyLoaded = false;
  final Map<DateTime, List<ScheduleSlot>> _weeks = {};
  final Map<DateTime, DateTime> _builtAt = {};
  List<ScheduleReport> reports = const [];
  bool loading = false;
  int progressDone = 0;
  int progressTotal = 0;

  List<ScheduleSlot>? week(DateTime start) => _weeks[start];
  DateTime? builtAt(DateTime start) => _builtAt[start];
  int get knownSeries => _history.length;

  /// Earliest release time of [chapterKey] seen in the « latest updates »
  /// of any site / MangaDex for one of these titles (any language), or null.
  DateTime? chapterReleaseDate(Iterable<String> titles, String chapterKey, {String? lang}) {
    DateTime? best;
    for (final t in titles) {
      if (TitleNormalizer.normalize(t).length < 3) continue;
      for (final l in lang == null ? const ['en', 'fr'] : [lang]) {
        final raw = _history[SeriesHistory.keyOf(t, l)]?.chapterDates[chapterKey];
        final d = raw == null ? null : DateTime.tryParse(raw);
        if (d != null && (best == null || d.isBefore(best))) best = d;
      }
    }
    return best;
  }

  /// Most recent release seen in the sites' « latest updates » feeds for
  /// one of these titles (any language), or null.
  DateTime? lastSeenRelease(Iterable<String> titles) {
    DateTime? best;
    for (final t in titles) {
      // A title in Cyrillic, Thai… (AniList synonyms) normalises to an
      // EMPTY key, shared by every such series of the feeds: it proved a
      // « recent chapter » for any work (2.3.15: « En pause » always empty).
      if (TitleNormalizer.normalize(t).length < 3) continue;
      for (final lang in const ['en', 'fr']) {
        final h = _history[SeriesHistory.keyOf(t, lang)];
        if (h == null || h.dates.isEmpty) continue;
        final d = DateTime.tryParse(h.dates.first);
        if (d != null && (best == null || d.isAfter(best))) best = d;
      }
    }
    return best;
  }

  File? _file(String name) {
    final dir = supportDir();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}schedule${Platform.pathSeparator}$name');
  }

  Future<void> _loadHistory() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    final file = _file('history.json');
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['series'] is! List) return;
      for (final item in raw['series'] as List) {
        final h = SeriesHistory.fromJson(item);
        if (h != null) _history[SeriesHistory.keyOf(h.title, h.lang)] = h;
      }
    } catch (e) {
      AppLog.info('Planning : historique illisible ($e)');
    }
  }

  Future<void> _saveHistory() async {
    final file = _file('history.json');
    if (file == null) return;
    // Series silent for 4 months are forgotten; the file stays small.
    final limit = DateTime.now().subtract(const Duration(days: 120));
    _history.removeWhere((_, h) {
      final newest = h.dates.isEmpty ? null : DateTime.tryParse(h.dates.first);
      return newest == null || newest.isBefore(limit);
    });
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'series': [for (final h in _history.values.take(8000)) h.toJson()],
      }));
      await tmp.rename(file.path);
    } catch (e) {
      AppLog.info('Planning : sauvegarde impossible ($e)');
    }
  }

  Future<void> _loadWeekSnapshot(DateTime start) async {
    if (_weeks.containsKey(start)) return;
    final file = _file('week-${start.year}-${start.month}-${start.day}.json');
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['slots'] is! List) return;
      final slots = [
        for (final s in raw['slots'] as List)
          if (slotFromJson(s) case final ScheduleSlot ok) ok,
      ];
      if (slots.isEmpty) return;
      _weeks[start] = slots;
      final at = DateTime.tryParse('${raw['builtAt']}');
      if (at != null) _builtAt[start] = at;
      reports = [
        for (final r in (raw['reports'] is List ? raw['reports'] as List : const []))
          if (r is Map && r['n'] is String)
            ScheduleReport(r['n'] as String, count: (r['c'] as int?) ?? 0,
                error: r['e'] as String?, group: (r['g'] as String?) ?? ''),
      ];
      notify();
    } catch (_) {}
  }

  Future<void> _saveWeekSnapshot(DateTime start) async {
    final slots = _weeks[start];
    final file = _file('week-${start.year}-${start.month}-${start.day}.json');
    if (slots == null || file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'builtAt': (_builtAt[start] ?? DateTime.now()).toIso8601String(),
        'slots': [for (final s in slots) slotToJson(s)],
        'reports': [
          for (final r in reports)
            {'n': r.name, 'c': r.count, if (r.error != null) 'e': r.error, 'g': r.group},
        ],
      }));
    } catch (_) {}
  }

  /// The planning of the week starting at [start]: shown at once from disk
  /// or memory, rebuilt in background when older than [maxAge].
  Future<void> load(DateTime start, {bool force = false,
      Duration maxAge = const Duration(hours: 3)}) async {
    await _loadHistory();
    await _loadWeekSnapshot(start);
    final at = _builtAt[start];
    if (!force && at != null && DateTime.now().difference(at) < maxAge) return;
    if (loading) return;
    loading = true;
    notify();
    try {
      await _build(start);
    } finally {
      loading = false;
      notify();
    }
  }

  Future<void> _build(DateTime start) async {
    final end = start.add(const Duration(days: 7));
    final now = DateTime.now();
    final slots = <ScheduleSlot>[];
    final newReports = <ScheduleReport>[];
    final webSites = sites();
    progressTotal = 4 + webSites.length;
    progressDone = 0;

    void step() {
      progressDone++;
      if (progressDone % 10 == 0) notify();
    }

    bool inWeek(DateTime d) => !d.isBefore(start) && d.isBefore(end);

    // 1. AniList: every broadcast of the week.
    try {
      final airings = await anilist.airingBetween(start, end);
      for (final (airing, info) in airings) {
        slots.add(ScheduleSlot(
          kind: SlotKind.anime,
          title: info.title,
          altTitles: info.altTitles,
          at: airing.airingAt,
          timeKnown: true,
          lang: 'ja',
          label: 'Épisode ${airing.episode}${info.episodes != null ? ' / ${info.episodes}' : ''}',
          state: airing.airingAt.isBefore(now) ? SlotState.released : SlotState.scheduled,
          providers: {'AniList'},
          coverUrl: info.cover,
          url: info.siteUrl,
          streams: info.streaming,
          work: info.toWork(),
          anime: info,
          note: info.streaming.isEmpty
              ? 'Diffusion japonaise'
              : 'Diffusion japonaise · simulcast : ${{for (final s in info.streaming) s.site}.join(', ')}',
        ));
      }
      newReports.add(ScheduleReport('AniList (animés)', count: airings.length, group: 'Animés'));
    } catch (e) {
      newReports.add(ScheduleReport('AniList (animés)', error: '$e', group: 'Animés'));
    }
    step();

    // 2. MangaDex: every EN and FR chapter of the last 3 weeks.
    for (final lang in const ['en', 'fr']) {
      try {
        final since = now.subtract(const Duration(days: 21));
        final recent = await mangadex.recentChapters(lang: lang, since: since,
            maxPages: lang == 'en' ? 15 : 8);
        // Most recent series first; titles and covers in batches of 100.
        final ids = <String>[];
        for (final (id, _) in recent) {
          if (!ids.contains(id)) ids.add(id);
        }
        final works = await mangadex.worksByIds(ids.take(600).toList());
        var count = 0;
        for (final (id, c) in recent) {
          final w = works[id];
          final at = c.publishedAt?.toLocal();
          if (w == null || at == null) continue;
          WeeklyScheduleBuilder.record(_history, title: w.title, lang: lang, at: at,
              coverUrl: w.coverUrl, sourceId: 'mangadex', workId: id, label: c.key.id);
          if (inWeek(at)) {
            count++;
            slots.add(ScheduleSlot(
              kind: SlotKind.comic, title: w.title, altTitles: w.altTitles, at: at,
              timeKnown: true, lang: lang, label: c.key.label, state: SlotState.released,
              providers: {'MangaDex'}, coverUrl: w.coverUrl, work: w,
            ));
          }
        }
        newReports.add(ScheduleReport('MangaDex ${lang.toUpperCase()}',
            count: count, group: 'Lectures'));
      } catch (e) {
        newReports.add(ScheduleReport('MangaDex ${lang.toUpperCase()}', error: '$e',
            group: 'Lectures'));
      }
      step();
    }

    // 2b. MangaUpdates: releases of the last days, every series.
    progressTotal++;
    try {
      final list = await MangaUpdatesClient(http).recentReleases(pages: 4)
          .timeout(const Duration(seconds: 60));
      var count = 0;
      for (final r in list) {
        WeeklyScheduleBuilder.record(_history, title: r.seriesTitle, lang: 'en', at: r.date,
            url: r.seriesUrl, sourceId: 'mangaupdates', workId: r.seriesUrl, label: r.chapter);
        if (inWeek(r.date)) {
          count++;
          slots.add(ScheduleSlot(
            kind: SlotKind.comic, title: r.seriesTitle, at: r.date, timeKnown: false,
            lang: 'en', label: 'Ch. ${r.chapter}', state: SlotState.released,
            providers: {'MangaUpdates'},
          ));
        }
      }
      newReports.add(ScheduleReport('MangaUpdates', count: count, group: 'Lectures',
          error: list.isEmpty ? 'aucune sortie lisible' : null));
    } catch (e) {
      newReports.add(ScheduleReport('MangaUpdates', error: '$e', group: 'Lectures'));
    }
    step();

    // 3. WEBTOON official daily schedule (EN, FR).
    for (final lang in const ['en', 'fr']) {
      final name = 'WEBTOON ${lang.toUpperCase()}';
      try {
        final uri = Uri.parse('https://www.webtoons.com/$lang/originals');
        final response = await http.get(uri,
            allowedHosts: const ['www.webtoons.com', 'webtoons.com', 'm.webtoons.com'],
            cache: true, timeout: const Duration(seconds: 15));
        if (!response.ok) throw 'HTTP ${response.status}';
        final daily = WebtoonDailyParser.parse(response.text, response.finalUri);
        if (daily.isEmpty) throw 'structure de la page non reconnue';
        for (final d in daily) {
          final day = start.add(Duration(days: d.weekday - 1));
          slots.add(ScheduleSlot(
            kind: SlotKind.comic, title: d.title, at: day, timeKnown: false, lang: lang,
            label: 'Nouvel épisode', state: SlotState.scheduled, providers: {name},
            coverUrl: d.coverUrl, url: d.url,
            note: 'Jour de mise à jour officiel',
          ));
        }
        newReports.add(ScheduleReport(name, count: daily.length, group: 'Lectures'));
      } catch (e) {
        newReports.add(ScheduleReport(name, error: '$e', group: 'Lectures'));
      }
      step();
    }

    // 4. Every directory site: « latest updates » blocks, 8 at a time.
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < webSites.length) {
        final site = webSites[cursor++];
        final lang = site.site.languages.contains('fr') && !site.site.languages.contains('en')
            ? 'fr' : (site.site.languages.isEmpty ? 'en' : site.site.languages.first);
        try {
          final list = await site.latestReleases().timeout(const Duration(seconds: 14));
          var count = 0;
          for (final r in list) {
            final at = r.at.toLocal();
            WeeklyScheduleBuilder.record(_history, title: r.seriesTitle, lang: lang, at: at,
                coverUrl: r.coverUrl, url: r.seriesUrl, sourceId: site.id,
                workId: r.seriesUrl, label: r.chapter.id);
            if (inWeek(at)) {
              count++;
              slots.add(ScheduleSlot(
                kind: SlotKind.comic, title: r.seriesTitle, at: at, timeKnown: r.precise,
                lang: lang, label: r.chapter.label, state: SlotState.released,
                providers: {site.name}, coverUrl: r.coverUrl, url: r.seriesUrl,
                work: WorkInfo(id: '${site.id}:${r.seriesUrl}', title: r.seriesTitle,
                    coverUrl: r.coverUrl, languages: [lang],
                    links: [SourceLink(sourceId: site.id, workId: r.seriesUrl)]),
              ));
            }
          }
          newReports.add(ScheduleReport(site.name, count: count, group: 'Sites',
              error: list.isEmpty ? 'aucune « dernière mise à jour » lisible' : null));
        } catch (e) {
          newReports.add(ScheduleReport(site.name, error: '$e', group: 'Sites'));
        }
        step();
      }
    }
    await Future.wait([for (var i = 0; i < (webSites.length < 8 ? webSites.length : 8); i++) worker()]);

    // 5. Library forecasts (rhythm of the followed works, anime of the list).
    final mine = entries().toList();
    for (final r in [
      ...ReleasePlanner.forecast(mine, langs: const ['en', 'fr'], now: now),
      ...animeReleases(),
    ]) {
      if (!r.dateKnown || !inWeek(r.date)) continue;
      slots.add(ScheduleSlot(
        kind: r.isAnime ? SlotKind.anime : SlotKind.comic,
        title: r.entry.work.title,
        altTitles: r.entry.work.altTitles,
        at: r.date,
        timeKnown: r.timeKnown,
        lang: r.isAnime ? 'ja' : r.lang,
        label: r.chapterLabel ?? 'Prochaine sortie',
        state: r.isAnime ? SlotState.scheduled : SlotState.estimated,
        providers: {'Ma bibliothèque'},
        coverUrl: r.entry.work.coverUrl,
        work: r.entry.work,
        note: r.note,
      ));
    }

    // 6. Projections from the rhythm of every series seen so far.
    slots.addAll(WeeklyScheduleBuilder.project(_history, start, now: now));

    _weeks[start] = WeeklyScheduleBuilder.merge(slots);
    _builtAt[start] = DateTime.now();
    reports = newReports;
    unawaited(_saveHistory());
    unawaited(_saveWeekSnapshot(start));
  }

  // ------------------------------------------------------------- storage

  static Map<String, dynamic> slotToJson(ScheduleSlot s) => {
        'k': s.kind.name,
        't': s.title,
        if (s.altTitles.isNotEmpty) 'a': s.altTitles.take(6).toList(),
        'at': s.at.toUtc().toIso8601String(),
        'tk': s.timeKnown,
        'l': s.lang,
        'lb': s.label,
        'st': s.state.name,
        'p': s.providers.toList(),
        if (s.coverUrl != null) 'c': s.coverUrl,
        if (s.url != null) 'u': s.url,
        if (s.note != null) 'n': s.note,
        if (s.streams.isNotEmpty)
          'sm': [for (final m in s.streams) {'s': m.site, 'u': m.url, if (m.language != null) 'l': m.language}],
        if (s.work != null) 'w': s.work!.toJson(),
      };

  static ScheduleSlot? slotFromJson(Object? raw) {
    if (raw is! Map || raw['t'] is! String || raw['at'] is! String) return null;
    final at = DateTime.tryParse(raw['at'] as String);
    if (at == null) return null;
    WorkInfo? work;
    if (raw['w'] is Map) {
      try {
        work = WorkInfo.fromJson((raw['w'] as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    return ScheduleSlot(
      kind: raw['k'] == 'anime' ? SlotKind.anime : SlotKind.comic,
      title: raw['t'] as String,
      altTitles: [for (final a in (raw['a'] is List ? raw['a'] as List : const [])) if (a is String) a],
      at: at.toLocal(),
      timeKnown: raw['tk'] == true,
      lang: (raw['l'] as String?) ?? 'en',
      label: (raw['lb'] as String?) ?? '',
      state: SlotState.values.firstWhere((s) => s.name == raw['st'],
          orElse: () => SlotState.estimated),
      providers: {for (final p in (raw['p'] is List ? raw['p'] as List : const [])) if (p is String) p},
      coverUrl: raw['c'] as String?,
      url: raw['u'] as String?,
      note: raw['n'] as String?,
      streams: [
        for (final m in (raw['sm'] is List ? raw['sm'] as List : const []))
          if (m is Map && m['s'] is String && m['u'] is String)
            StreamingLink(site: m['s'] as String, url: m['u'] as String, language: m['l'] as String?),
      ],
      work: work,
    );
  }
}
