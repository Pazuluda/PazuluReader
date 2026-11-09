import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'models.dart';

/// One series listed in a site's catalogue (title + address of its page).
class IndexedTitle {
  const IndexedTitle(this.title, this.url, {this.fromSlug = false});

  final String title;
  final String url;

  /// Title rebuilt from the address (sitemaps give no title).
  final bool fromSlug;

  List<Object> toJson() => [title, url, if (fromSlug) 1];

  static IndexedTitle? fromJson(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    return IndexedTitle('${raw[0]}', '${raw[1]}', fromSlug: raw.length > 2 && raw[2] == 1);
  }

  /// « disastrous-necromancer » → « Disastrous Necromancer ».
  static String titleFromSlug(String slug) => slug
      .split(RegExp(r'[-_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// A work as the whole index sees it: one title, every site that lists it.
class IndexedWork {
  IndexedWork(this.key, this.title, this.links);

  final String key;
  final String title;
  final List<SourceLink> links;

  WorkInfo toWork() => WorkInfo(id: 'index:$key', title: title, links: links);
}

/// Local index of the catalogues of every site (Engine 2.0).
///
/// Each site's list of series (titles + addresses, metadata only, never an
/// image or a chapter page) is read once, kept on disk and refreshed every
/// day. Any work — library, Discover, search — then knows ALL the sites that
/// have it at once, instead of asking 200 sites one by one.
///
/// Hundreds of thousands of titles: reading, normalising, saving and
/// sorting run in a background isolate, never on the screen's thread.
class SiteTitleIndex {
  SiteTitleIndex(this.file);

  final File? file;
  final Map<String, List<IndexedTitle>> bySource = {};
  final Map<String, List<String>> _keysOf = {};
  final Map<String, DateTime> crawledAt = {};

  /// Sites whose catalogue could not be read (dead, anti-robot…), with the
  /// time of the attempt: not retried for a while.
  final Map<String, DateTime> failedAt = {};

  final Map<String, List<(String, IndexedTitle)>> _byKey = {};
  final Map<String, List<(String, IndexedTitle)>> _byLoose = {};
  List<IndexedWork>? _works;
  Future<void>? _preparing;
  int _titleCount = 0;
  int _version = 0;

  static final RegExp _nonAscii = RegExp(r'[^\x00-\x7f]');
  static final RegExp _quotes = RegExp(r"[’'`´]");
  static final RegExp _separators =
      RegExp(r'[^a-z0-9぀-ヿ一-鿿가-힯]+');
  static const _from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  static const _to = 'aaaaaaceeeeiiiinooooouuuuyyoa';

  /// Normalised title: lower case, no accents, no punctuation.
  static String norm(String raw) {
    var s = raw.toLowerCase();
    if (_nonAscii.hasMatch(s)) {
      final b = StringBuffer();
      for (final rune in s.runes) {
        final ch = String.fromCharCode(rune);
        final i = _from.indexOf(ch);
        b.write(i >= 0 ? _to[i] : ch);
      }
      s = b.toString();
    }
    s = s.replaceAll(_quotes, '').replaceAll(_separators, ' ').trim();
    return s.contains('  ') ? s.replaceAll(RegExp(r'\s+'), ' ') : s;
  }

  int get siteCount => bySource.values.where((l) => l.isNotEmpty).length;
  int get titleCount => _titleCount;

  bool isFresh(String sourceId, {Duration maxAge = const Duration(hours: 24)}) {
    final at = crawledAt[sourceId];
    return at != null && DateTime.now().difference(at) < maxAge;
  }

  /// The site's catalogue is known (recently enough to trust its absence).
  /// A list of fewer than 30 series is probably one page of « latest
  /// updates », not the whole catalogue: the site is still searched.
  bool covers(String sourceId) => isFresh(sourceId, maxAge: const Duration(days: 7)) &&
      (bySource[sourceId]?.length ?? 0) >= 30;

  /// Looser form of a normalised title, for sites that write it a little
  /// differently: « The World After the Fall » = « World After the Fall »,
  /// « Solo Leveling (Official) » = « Solo Leveling », « Hero’s » = « Heros ».
  /// The chapter lists are still checked against the other sources before
  /// a site is attached, so two different works are not merged.
  static String loose(String normalised) {
    var s = ' $normalised ';
    s = s.replaceAll(RegExp(r' (the|a|an|le|la|les|l) '), ' ');
    s = s.replaceAll(RegExp(r' (official|manga|manhwa|manhua|webtoon|comic|comics|raw|scan|scans|vf|fr|en|english|french) '), ' ');
    s = s.replaceAll(' and ', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.replaceAll(' ', '');
  }

  void _unlink(String sourceId) {
    final old = bySource[sourceId];
    final keys = _keysOf[sourceId];
    if (old == null || keys == null) return;
    _titleCount -= old.length;
    for (final k in keys.toSet()) {
      final list = _byKey[k];
      if (list != null) {
        list.removeWhere((p) => p.$1 == sourceId);
        if (list.isEmpty) _byKey.remove(k);
      }
      final l = loose(k);
      final looseList = _byLoose[l];
      if (looseList != null) {
        looseList.removeWhere((p) => p.$1 == sourceId);
        if (looseList.isEmpty) _byLoose.remove(l);
      }
    }
  }

  void _link(String sourceId, List<IndexedTitle> titles, List<String> keys) {
    bySource[sourceId] = titles;
    _keysOf[sourceId] = keys;
    _titleCount += titles.length;
    for (var i = 0; i < titles.length; i++) {
      final k = keys[i];
      if (k.length < 2) continue;
      (_byKey[k] ??= []).add((sourceId, titles[i]));
      final l = loose(k);
      if (l.length >= 4) (_byLoose[l] ??= []).add((sourceId, titles[i]));
    }
    _works = null;
    _version++;
  }

  /// Adds / replaces one site's catalogue (titles normalised in background).
  Future<void> put(String sourceId, List<IndexedTitle> titles) async {
    final keys = titles.length > 3000
        ? await _normInBackground(titles)
        : [for (final t in titles) norm(t.title)];
    _unlink(sourceId);
    _link(sourceId, titles, keys);
    crawledAt[sourceId] = DateTime.now();
    failedAt.remove(sourceId);
  }

  void fail(String sourceId) {
    failedAt[sourceId] = DateTime.now();
  }

  /// Every site listing one of [titles] (exact normalised title), one
  /// series page per site.
  List<SourceLink> linksFor(Iterable<String> titles) {
    final seen = <String>{};
    final out = <SourceLink>[];
    for (final t in titles) {
      final k = norm(t);
      if (k.length < 2) continue;
      for (final (sourceId, item) in _byKey[k] ?? const <(String, IndexedTitle)>[]) {
        if (seen.add(sourceId)) out.add(SourceLink(sourceId: sourceId, workId: item.url));
      }
    }
    // Then the sites that write the title a little differently.
    for (final t in titles) {
      final l = loose(norm(t));
      if (l.length < 4) continue;
      for (final (sourceId, item) in _byLoose[l] ?? const <(String, IndexedTitle)>[]) {
        if (seen.add(sourceId)) out.add(SourceLink(sourceId: sourceId, workId: item.url));
      }
    }
    return out;
  }

  /// All the works of all the sites, A → Z — null while being prepared in
  /// background (call [prepareWorks]).
  List<IndexedWork>? get works => _works;

  Future<void> prepareWorks() {
    if (_works != null) return Future.value();
    return _preparing ??= () async {
      final version = _version;
      final works = await _worksInBackground(Map.of(bySource), Map.of(_keysOf));
      // Changed meanwhile (a site was re-indexed): prepared again next time.
      if (version == _version) _works = works;
      _preparing = null;
    }();
  }

  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    final path = f.path;
    try {
      final loaded = await _loadInBackground(path);
      for (final e in loaded.$1.entries) {
        _link(e.key, e.value.$2, e.value.$3);
        final at = DateTime.tryParse(e.value.$1 ?? '');
        if (at != null) crawledAt[e.key] = at;
      }
      for (final e in loaded.$2.entries) {
        final d = DateTime.tryParse(e.value);
        if (d != null) failedAt[e.key] = d;
      }
    } catch (_) {
      // A damaged index is rebuilt by the next crawl.
    }
  }

  Future<void>? _saving;

  Future<void> save() async {
    while (_saving != null) {
      await _saving;
    }
    final f = file;
    if (f == null) return;
    final path = f.path;
    final sites = {
      for (final e in bySource.entries)
        e.key: (crawledAt[e.key]?.toIso8601String(), e.value),
    };
    final failed = {for (final e in failedAt.entries) e.key: e.value.toIso8601String()};
    final job = _saveInBackground(path, sites, failed);
    _saving = job;
    try {
      await job;
    } catch (_) {
      // Next save will retry.
    } finally {
      _saving = null;
    }
  }

  // Background isolates. Static functions: the closures sent to the isolate
  // hold only their arguments (never this object, its futures or files).

  static Future<List<String>> _normInBackground(List<IndexedTitle> titles) =>
      Isolate.run(() => [for (final t in titles) norm(t.title)]);

  static Future<List<IndexedWork>> _worksInBackground(
          Map<String, List<IndexedTitle>> bySource, Map<String, List<String>> keysOf) =>
      Isolate.run(() {
        final snapshot = <String, List<(String, IndexedTitle)>>{};
        for (final e in bySource.entries) {
          final keys = keysOf[e.key] ?? const <String>[];
          for (var i = 0; i < e.value.length && i < keys.length; i++) {
            if (keys[i].length < 2) continue;
            (snapshot[keys[i]] ??= []).add((e.key, e.value[i]));
          }
        }
        final out = <IndexedWork>[];
        for (final e in snapshot.entries) {
          final real = e.value.where((p) => !p.$2.fromSlug).toList();
          final title = (real.isNotEmpty ? real.first : e.value.first).$2.title;
          final seen = <String>{};
          out.add(IndexedWork(e.key, title, [
            for (final (sourceId, item) in e.value)
              if (seen.add(sourceId)) SourceLink(sourceId: sourceId, workId: item.url),
          ]));
        }
        out.sort((a, b) => a.key.compareTo(b.key));
        return out;
      });

  static Future<(Map<String, (String?, List<IndexedTitle>, List<String>)>, Map<String, String>)>
      _loadInBackground(String path) => Isolate.run(() {
            final raw = jsonDecode(File(path).readAsStringSync());
            final sites = <String, (String?, List<IndexedTitle>, List<String>)>{};
            final failed = <String, String>{};
            if (raw is Map && raw['sites'] is Map) {
              for (final e in (raw['sites'] as Map).entries) {
                final v = e.value;
                if (v is! Map) continue;
                final titles = [
                  for (final t in (v['titles'] as List? ?? const []))
                    if (IndexedTitle.fromJson(t) case final IndexedTitle ok) ok,
                ];
                sites['${e.key}'] =
                    (v['at'] as String?, titles, [for (final t in titles) norm(t.title)]);
              }
              if (raw['failed'] is Map) {
                for (final e in (raw['failed'] as Map).entries) {
                  failed['${e.key}'] = '${e.value}';
                }
              }
            }
            return (sites, failed);
          });

  static Future<void> _saveInBackground(String path,
          Map<String, (String?, List<IndexedTitle>)> sites, Map<String, String> failed) =>
      Isolate.run(() {
        final tmp = File('$path.tmp');
        tmp.writeAsStringSync(jsonEncode({
          'version': 1,
          'sites': {
            for (final e in sites.entries)
              e.key: {
                'at': e.value.$1,
                'titles': [for (final t in e.value.$2) t.toJson()],
              },
          },
          'failed': failed,
        }), flush: true);
        final target = File(path);
        if (target.existsSync()) target.deleteSync();
        tmp.renameSync(path);
      });
}
