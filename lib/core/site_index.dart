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

  /// Former single file (site-index.json, migrated once). The index now
  /// lives in a folder next to it: one small file per site, written when
  /// that site is re-read (never the whole index again).
  final File? file;
  final Map<String, List<IndexedTitle>> bySource = {};
  final Map<String, List<String>> _keysOf = {};
  final Map<String, List<String>> _looseOf = {};
  final Map<String, DateTime> crawledAt = {};

  /// Sites whose catalogue could not be read (dead, anti-robot…), with the
  /// time of the attempt: not retried for a while.
  final Map<String, DateTime> failedAt = {};

  Map<String, List<(String, IndexedTitle)>> _byKey = {};
  Map<String, List<(String, IndexedTitle)>> _byLoose = {};
  List<IndexedWork>? _works;
  bool _worksStale = false;
  Future<void>? _preparing;
  int _titleCount = 0;
  int _version = 0;

  /// Finished loading from disk (the app is usable before).
  bool loaded = false;

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

  static final RegExp _articles = RegExp(r' (the|a|an|le|la|les|l) ');
  static final RegExp _noise = RegExp(
      r' (official|manga|manhwa|manhua|webtoon|comic|comics|raw|scan|scans|vf|fr|en|english|french) ');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Looser form of a normalised title, for sites that write it a little
  /// differently: « The World After the Fall » = « World After the Fall »,
  /// « Solo Leveling (Official) » = « Solo Leveling », « Hero’s » = « Heros ».
  /// The chapter lists are still checked against the other sources before
  /// a site is attached, so two different works are not merged.
  static String loose(String normalised) {
    var s = ' $normalised ';
    s = s.replaceAll(_articles, ' ');
    s = s.replaceAll(_noise, ' ');
    s = s.replaceAll(' and ', ' ');
    s = s.replaceAll(_spaces, ' ').trim();
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
    }
    for (final l in (_looseOf[sourceId] ?? const <String>[]).toSet()) {
      final looseList = _byLoose[l];
      if (looseList != null) {
        looseList.removeWhere((p) => p.$1 == sourceId);
        if (looseList.isEmpty) _byLoose.remove(l);
      }
    }
  }

  void _link(String sourceId, List<IndexedTitle> titles, List<String> keys, List<String> looseKeys) {
    bySource[sourceId] = titles;
    _keysOf[sourceId] = keys;
    _looseOf[sourceId] = looseKeys;
    _titleCount += titles.length;
    for (var i = 0; i < titles.length; i++) {
      final k = keys[i];
      if (k.length < 2) continue;
      (_byKey[k] ??= []).add((sourceId, titles[i]));
      final l = looseKeys[i];
      if (l.length >= 4) (_byLoose[l] ??= []).add((sourceId, titles[i]));
    }
    // The A → Z list is kept (search keeps working) and rebuilt later,
    // once, instead of after every site.
    if (_works != null) _worksStale = true;
    _version++;
  }

  /// Adds / replaces one site's catalogue (titles normalised in background)
  /// and writes that site's file only.
  Future<void> put(String sourceId, List<IndexedTitle> titles) async {
    final (keys, looseKeys) = titles.length > 2000
        ? await _keysInBackground(titles)
        : _keysFor(titles);
    _unlink(sourceId);
    _link(sourceId, titles, keys, looseKeys);
    crawledAt[sourceId] = DateTime.now();
    failedAt.remove(sourceId);
    final dir = folder;
    if (dir != null) {
      _pendingWrites.add(_writeSite(dir.path, sourceId, crawledAt[sourceId]!.toIso8601String(), titles));
    }
  }

  static (List<String>, List<String>) _keysFor(List<IndexedTitle> titles) {
    final keys = [for (final t in titles) norm(t.title)];
    return (keys, [for (final k in keys) loose(k)]);
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

  /// The site whose catalogue lists this exact series address, if any.
  IndexedTitle? titleAt(String sourceId, String url) {
    for (final t in bySource[sourceId] ?? const <IndexedTitle>[]) {
      if (t.url == url) return t;
    }
    return null;
  }

  /// All the works of all the sites, A → Z — null while being prepared in
  /// background (call [prepareWorks]). After a catalogue update the
  /// previous list stays usable until the new one is ready.
  List<IndexedWork>? get works => _works;

  Future<void> prepareWorks() {
    if (_works != null && !_worksStale) return Future.value();
    return _preparing ??= () async {
      try {
        final version = _version;
        final works = await _worksInBackground(await _snapshot(_byKey));
        _works = works;
        // Changed meanwhile (a site was re-indexed): rebuilt next time.
        _worksStale = version != _version;
      } finally {
        _preparing = null;
      }
    }();
  }

  /// Searches the A → Z list without blocking the screen: titles starting
  /// with [query] first (binary search), then titles containing it, read
  /// 20 000 at a time with a pause in between. [cancelled] stops a search
  /// that a new keystroke made useless.
  static Future<List<IndexedWork>> search(List<IndexedWork> works, String query,
      {int limit = 8, bool Function()? cancelled}) async {
    final q = norm(query);
    if (q.length < 2) return const [];
    final out = <IndexedWork>[];
    final seen = <String>{};
    // Sorted by key: the titles starting with q are contiguous.
    var lo = 0, hi = works.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (works[mid].key.compareTo(q) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < works.length && out.length < limit && works[i].key.startsWith(q); i++) {
      out.add(works[i]);
      seen.add(works[i].key);
    }
    if (out.length >= limit) return out;
    for (var i = 0; i < works.length; i++) {
      if (i > 0 && i % 20000 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (cancelled?.call() ?? false) return out;
      }
      final w = works[i];
      if (w.key.contains(q) && seen.add(w.key)) {
        out.add(w);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  final List<Future<void>> _pendingWrites = [];

  Directory? get folder {
    final f = file;
    return f == null ? null : Directory('${f.parent.path}${Platform.pathSeparator}site-index');
  }

  /// Loads the index from disk, entirely in a background isolate (reading,
  /// normalising and building the lookup tables); the screen's thread only
  /// receives the finished tables.
  Future<void> load() async {
    final dir = folder;
    if (dir == null) {
      loaded = true;
      return;
    }
    try {
      final r = await _loadInBackground(dir.path, file!.path);
      bySource.addAll(r.bySource);
      _keysOf.addAll(r.keysOf);
      _byKey = r.byKey;
      _byLoose = r.byLoose;
      _looseOf.addAll(r.looseOf);
      _titleCount = r.titleCount;
      // A → Z list built by the same isolate (handed over without a copy).
      _works = r.works;
      _worksStale = false;
      for (final e in r.at.entries) {
        final at = DateTime.tryParse(e.value);
        if (at != null) crawledAt[e.key] = at;
      }
      for (final e in r.failed.entries) {
        final d = DateTime.tryParse(e.value);
        if (d != null) failedAt[e.key] = d;
      }
      _version++;
    } catch (_) {
      // A damaged index is rebuilt by the next crawl.
    } finally {
      loaded = true;
    }
  }

  /// Writes the sites re-read since the last call and the list of failed
  /// sites (small file).
  Future<void> save() async {
    final pending = List.of(_pendingWrites);
    _pendingWrites.clear();
    for (final w in pending) {
      try {
        await w;
      } catch (_) {}
    }
    final dir = folder;
    if (dir == null) return;
    try {
      await dir.create(recursive: true);
      final meta = File('${dir.path}${Platform.pathSeparator}_echecs.json');
      await meta.writeAsString(jsonEncode({
        for (final e in failedAt.entries) e.key: e.value.toIso8601String(),
      }));
    } catch (_) {
      // Next save will retry.
    }
  }

  // Background isolates. Static functions: the closures sent to the isolate
  // hold only their arguments (never this object, its futures or files).

  static String fileNameFor(String sourceId) =>
      '${sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.json';

  static Future<(List<String>, List<String>)> _keysInBackground(List<IndexedTitle> titles) =>
      Isolate.run(() => _keysFor(titles));

  static Future<void> _writeSite(String dir, String sourceId, String at, List<IndexedTitle> titles) =>
      Isolate.run(() {
        Directory(dir).createSync(recursive: true);
        final path = '$dir${Platform.pathSeparator}${fileNameFor(sourceId)}';
        final tmp = File('$path.tmp');
        tmp.writeAsStringSync(jsonEncode({
          'id': sourceId,
          'at': at,
          'titles': [for (final t in titles) t.toJson()],
        }), flush: true);
        final target = File(path);
        if (target.existsSync()) target.deleteSync();
        tmp.renameSync(path);
      });

  /// Copy of the lookup table, built a slice at a time so the screen
  /// keeps responding.
  static Future<List<(String, List<(String, IndexedTitle)>)>> _snapshot(
      Map<String, List<(String, IndexedTitle)>> byKey) async {
    final out = <(String, List<(String, IndexedTitle)>)>[];
    var n = 0;
    for (final e in byKey.entries) {
      out.add((e.key, List.of(e.value)));
      if (++n % 20000 == 0) await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  static List<IndexedWork> _buildWorks(Iterable<(String, List<(String, IndexedTitle)>)> entries) {
    final out = <IndexedWork>[];
    for (final (key, items) in entries) {
      if (items.isEmpty) continue;
      final real = items.where((p) => !p.$2.fromSlug).toList();
      final title = (real.isNotEmpty ? real.first : items.first).$2.title;
      final seen = <String>{};
      out.add(IndexedWork(key, title, [
        for (final (id, t) in items)
          if (seen.add(id)) SourceLink(sourceId: id, workId: t.url),
      ]));
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  static Future<List<IndexedWork>> _worksInBackground(
          List<(String, List<(String, IndexedTitle)>)> snapshot) =>
      Isolate.run(() => _buildWorks(snapshot));

  static Future<_Loaded> _loadInBackground(String dir, String legacyPath) => Isolate.run(() {
        final r = _Loaded();
        final sites = <String, (String?, List<IndexedTitle>)>{};
        final folder = Directory(dir);
        if (folder.existsSync()) {
          for (final f in folder.listSync().whereType<File>()) {
            final name = f.uri.pathSegments.last;
            if (!name.endsWith('.json')) continue;
            try {
              final raw = jsonDecode(f.readAsStringSync());
              if (name == '_echecs.json') {
                if (raw is Map) {
                  for (final e in raw.entries) {
                    r.failed['${e.key}'] = '${e.value}';
                  }
                }
                continue;
              }
              if (raw is! Map || raw['id'] is! String) continue;
              sites[raw['id'] as String] = (raw['at'] as String?, [
                for (final t in (raw['titles'] as List? ?? const []))
                  if (IndexedTitle.fromJson(t) case final IndexedTitle ok) ok,
              ]);
            } catch (_) {
              // one damaged site file: that site is re-read by the next crawl
            }
          }
        }
        // Former single file: migrated once into one file per site.
        final legacy = File(legacyPath);
        if (legacy.existsSync()) {
          try {
            final raw = jsonDecode(legacy.readAsStringSync());
            if (raw is Map && raw['sites'] is Map) {
              folder.createSync(recursive: true);
              for (final e in (raw['sites'] as Map).entries) {
                final v = e.value;
                final id = '${e.key}';
                if (v is! Map || sites.containsKey(id)) continue;
                final titles = [
                  for (final t in (v['titles'] as List? ?? const []))
                    if (IndexedTitle.fromJson(t) case final IndexedTitle ok) ok,
                ];
                sites[id] = (v['at'] as String?, titles);
                final path = '$dir${Platform.pathSeparator}${fileNameFor(id)}';
                File(path).writeAsStringSync(jsonEncode({
                  'id': id,
                  'at': v['at'],
                  'titles': [for (final t in titles) t.toJson()],
                }));
              }
              if (raw['failed'] is Map) {
                for (final e in (raw['failed'] as Map).entries) {
                  r.failed['${e.key}'] = '${e.value}';
                }
              }
            }
            legacy.deleteSync();
          } catch (_) {
            // kept as it is; read again next time
          }
        }
        for (final e in sites.entries) {
          final titles = e.value.$2;
          final (keys, looseKeys) = _keysFor(titles);
          r.bySource[e.key] = titles;
          r.keysOf[e.key] = keys;
          r.looseOf[e.key] = looseKeys;
          r.titleCount += titles.length;
          if (e.value.$1 != null) r.at[e.key] = e.value.$1!;
          for (var i = 0; i < titles.length; i++) {
            final k = keys[i];
            if (k.length < 2) continue;
            (r.byKey[k] ??= []).add((e.key, titles[i]));
            final l = looseKeys[i];
            if (l.length >= 4) (r.byLoose[l] ??= []).add((e.key, titles[i]));
          }
        }
        r.works = _buildWorks([for (final e in r.byKey.entries) (e.key, e.value)]);
        return r;
      });
}

/// What the loading isolate hands back (built tables, ready to use).
class _Loaded {
  final Map<String, List<IndexedTitle>> bySource = {};
  final Map<String, List<String>> keysOf = {};
  final Map<String, List<String>> looseOf = {};
  List<IndexedWork> works = const [];
  final Map<String, List<(String, IndexedTitle)>> byKey = {};
  final Map<String, List<(String, IndexedTitle)>> byLoose = {};
  final Map<String, String> at = {};
  final Map<String, String> failed = {};
  int titleCount = 0;
}
