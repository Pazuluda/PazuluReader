import 'dart:convert';

import '../../engine/http/engine_http.dart';
import '../site_index.dart';

/// One release listed by MangaUpdates (a scanlation group published a
/// chapter of a series on that day).
class MuRelease {
  const MuRelease({required this.seriesTitle, required this.chapter, required this.date,
      this.seriesId, this.seriesUrl});

  final String seriesTitle;
  final String chapter;
  final DateTime date;
  final int? seriesId;
  final String? seriesUrl;
}

/// MangaUpdates (www.mangaupdates.com), public API v1: release history of
/// every series (all scanlation groups), official status. Metadata only.
///
/// It is one more independent source for the planning: the real dates of
/// the past chapters give the rhythm (weekly, every 2 weeks…) and the day
/// of the week of a series, even when no site of the library gave a date.
class MangaUpdatesClient {
  MangaUpdatesClient(this.http);

  final EngineHttpClient http;

  static const host = 'api.mangaupdates.com';
  static const _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  Future<String> _get(String path) async {
    final r = await http.get(Uri.https(host, path), allowedHosts: const [host],
        headers: const {'Accept': 'application/json'}, cache: true,
        timeout: const Duration(seconds: 15), sourceId: 'mangaupdates');
    if (!r.ok) throw 'HTTP ${r.status}';
    return r.text;
  }

  Future<String> _post(String path, Map<String, Object?> body) async {
    final r = await http.get(Uri.https(host, path), method: 'POST', allowedHosts: const [host],
        headers: _headers, body: jsonEncode(body), cache: true,
        timeout: const Duration(seconds: 15), sourceId: 'mangaupdates');
    if (!r.ok) throw 'HTTP ${r.status}';
    return r.text;
  }

  /// Releases of the last days, every series (one page = ~ 50 releases).
  Future<List<MuRelease>> recentReleases({int pages = 3}) async {
    final out = <MuRelease>[];
    for (var page = 1; page <= pages; page++) {
      final list = parseDays(await _get('/v1/releases/days?include_metadata=true&page=$page'));
      out.addAll(list);
      if (list.isEmpty) break;
    }
    return out;
  }

  /// The MangaUpdates series of a work (same title or alternative title),
  /// or null when no result is the same work.
  Future<int?> findSeries(List<String> titles) async {
    for (final t in titles.take(3)) {
      if (SiteTitleIndex.norm(t).length < 3) continue;
      final id = pickSeries(await _post('/v1/series/search', {'search': t, 'perpage': 8}), titles);
      if (id != null) return id;
    }
    return null;
  }

  /// Status label (« 120 Chapters (Ongoing) », « Complete »…) of a series.
  Future<String?> status(int seriesId) async => parseStatus(await _get('/v1/series/$seriesId'));

  /// Earliest release date of each chapter of a series (all groups).
  Future<Map<String, DateTime>> chapterDates(int seriesId) async => parseReleaseDates(
      await _post('/v1/releases/search', {
        'search': '$seriesId',
        'search_type': 'series',
        'perpage': 60,
      }));

  // ---------------------------------------------------------------- parsers

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _day(Object? raw) {
    if (raw is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// « 29a », « 28-29 », « 12.5 » → « 29 », « 29 », « 12.5 » (highest of a range).
  static String? chapterKey(Object? raw) {
    final s = '${raw ?? ''}';
    final nums = RegExp(r'\d+(?:\.\d+)?').allMatches(s).map((m) => double.parse(m[0]!)).toList();
    if (nums.isEmpty) return null;
    final n = nums.reduce((a, b) => a > b ? a : b);
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  static List<MuRelease> parseDays(String raw) {
    final json = _decode(raw);
    final results = json is Map ? json['results'] : null;
    if (results is! List) return const [];
    final out = <MuRelease>[];
    for (final r in results) {
      if (r is! Map) continue;
      final record = r['record'];
      final meta = r['metadata'];
      final series = meta is Map ? meta['series'] : null;
      if (record is! Map) continue;
      final title = (series is Map ? series['title'] : null) ?? record['title'];
      final chapter = chapterKey(record['chapter']);
      final date = _day(record['release_date']);
      if (title is! String || title.trim().isEmpty || chapter == null || date == null) continue;
      out.add(MuRelease(
        seriesTitle: title.trim(),
        chapter: chapter,
        date: date,
        seriesId: series is Map && series['series_id'] is int ? series['series_id'] as int : null,
        seriesUrl: series is Map && series['url'] is String ? series['url'] as String : null,
      ));
    }
    return out;
  }

  /// Series id of the search result that is the same work (exact or loose
  /// normalised title, including the title the search matched).
  static int? pickSeries(String raw, List<String> titles) {
    final json = _decode(raw);
    final results = json is Map ? json['results'] : null;
    if (results is! List) return null;
    final exact = {for (final t in titles) SiteTitleIndex.norm(t)}..removeWhere((t) => t.length < 3);
    final loose = {for (final t in exact) SiteTitleIndex.loose(t)}..removeWhere((t) => t.length < 4);
    for (final r in results) {
      if (r is! Map) continue;
      final record = r['record'];
      if (record is! Map || record['series_id'] is! int) continue;
      final names = [record['title'], r['hit_title']].whereType<String>();
      for (final n in names) {
        final k = SiteTitleIndex.norm(n);
        if (exact.contains(k) || loose.contains(SiteTitleIndex.loose(k))) {
          return record['series_id'] as int;
        }
      }
    }
    return null;
  }

  static String? parseStatus(String raw) {
    final json = _decode(raw);
    if (json is! Map) return null;
    final status = json['status'];
    // (« completed » means « completely scanlated », not « finished ».)
    if (status is String && status.trim().isNotEmpty) {
      // « 5 Volumes (Ongoing) » → « Ongoing ».
      final m = RegExp(r'\(([^)]+)\)').allMatches(status).map((m) => m[1]!).toList();
      return m.isEmpty ? status.trim() : m.first.trim();
    }
    return null;
  }

  static Map<String, DateTime> parseReleaseDates(String raw) {
    final out = <String, DateTime>{};
    for (final r in parseDays(raw)) {
      final old = out[r.chapter];
      if (old == null || r.date.isBefore(old)) out[r.chapter] = r.date;
    }
    return out;
  }
}
