import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'achievements.dart';
import 'models.dart';

/// Toutes les données personnelles de l'utilisateur.
class LibraryData {
  LibraryData({
    Settings? settings,
    Map<String, LibraryEntry>? entries,
    List<UpdateItem>? updates,
    ActivityLog? activity,
  })  : settings = settings ?? Settings(),
        entries = entries ?? <String, LibraryEntry>{},
        updates = updates ?? <UpdateItem>[],
        activity = activity ?? ActivityLog();

  Settings settings;
  Map<String, LibraryEntry> entries;
  List<UpdateItem> updates;

  /// Reading / watching journal, levels and achievements.
  ActivityLog activity;

  Map<String, dynamic> toJson() => {
        'schemaVersion': LibraryStore.schemaVersion,
        'settings': settings.toJson(),
        'entries': entries.values.map((e) => e.toJson()).toList(),
        'updates': updates.map((u) => u.toJson()).toList(),
        'activity': activity.toJson(),
      };

  factory LibraryData.fromJson(Map<String, dynamic> json) {
    final migrated = LibraryStore.migrate(json);
    final entries = <String, LibraryEntry>{};
    for (final e in (migrated['entries'] as List? ?? const [])) {
      if (e is! Map) continue;
      final entry = LibraryEntry.fromJson(e.cast<String, dynamic>());
      entries[entry.work.id] = entry;
    }
    return LibraryData(
      settings: Settings.fromJson(
        (migrated['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      entries: entries,
      updates: [
        for (final u in (migrated['updates'] as List? ?? const []))
          if (u is Map) UpdateItem.fromJson(u.cast<String, dynamic>()),
      ],
      activity: ActivityLog.fromJson(migrated['activity']),
    );
  }
}

class LoadResult {
  const LoadResult(this.data, {this.warning});

  final LibraryData data;
  final String? warning;
}

/// Stockage local : un fichier JSON versionné, écrit de façon atomique,
/// avec copie de secours et sauvegardes automatiques tournantes.
///
/// v0.1 : JSON. Le passage à SQLite (Drift) est prévu quand la
/// bibliothèque grossira ; [migrate] garantit la reprise des données.
class LibraryStore {
  LibraryStore(this.dir);

  static const int schemaVersion = 1;
  static const String backupFormat = 'pazulu-backup';
  static const int backupFormatVersion = 1;

  final Directory dir;

  String get _sep => Platform.pathSeparator;
  File get _file => File('${dir.path}${_sep}library.json');
  File get _backup => File('${dir.path}${_sep}library.json.bak');
  File get _tmp => File('${dir.path}${_sep}library.json.tmp');
  Directory get autoBackupDir => Directory('${dir.path}${_sep}sauvegardes');

  /// Fait évoluer un ancien format vers [schemaVersion].
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    var version = (json['schemaVersion'] as int?) ?? 1;
    final out = Map<String, dynamic>.from(json);
    // Exemple pour les versions futures :
    // if (version == 1) { ...transformer...; version = 2; }
    if (version > schemaVersion) {
      throw FormatException(
        'Données créées par une version plus récente de Pazulu (format $version).',
      );
    }
    out['schemaVersion'] = version;
    return out;
  }

  Future<LoadResult> load() async {
    if (!await dir.exists()) await dir.create(recursive: true);
    if (!await _file.exists()) {
      if (await _backup.exists()) {
        final data = await _read(_backup);
        if (data != null) {
          return LoadResult(data, warning: 'Bibliothèque restaurée depuis la copie de secours.');
        }
      }
      return LoadResult(LibraryData());
    }
    final data = await _read(_file);
    if (data != null) return LoadResult(data);

    // Fichier principal illisible : on le conserve et on tente la copie.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _file.copy('${dir.path}${_sep}library.corrompu.$stamp.json');
    if (await _backup.exists()) {
      final backup = await _read(_backup);
      if (backup != null) {
        return LoadResult(
          backup,
          warning: 'Fichier de bibliothèque endommagé : copie de secours utilisée.',
        );
      }
    }
    return LoadResult(
      LibraryData(),
      warning: 'Bibliothèque illisible. Le fichier a été conservé à part.',
    );
  }

  Future<LibraryData?> _read(File f) async {
    try {
      final json = jsonDecode(await f.readAsString());
      if (json is! Map) return null;
      return LibraryData.fromJson(json.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(LibraryData data) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    final text = jsonEncode(data.toJson());
    await _tmp.writeAsString(text, flush: true);
    if (await _file.exists()) {
      await _file.copy(_backup.path);
      await _file.delete();
    }
    await _tmp.rename(_file.path);
  }

  /// Une sauvegarde automatique par jour, 7 conservées.
  Future<void> autoBackup(LibraryData data, String appVersion) async {
    final d = autoBackupDir;
    if (!await d.exists()) await d.create(recursive: true);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final target = File('${d.path}${_sep}auto-$today.pazulu');
    if (await target.exists()) return;
    await target.writeAsString(encodeBackup(data, appVersion), flush: true);

    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pazulu') && f.path.contains('auto-'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(7)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Fichier de sauvegarde portable `.pazulu`
  // -------------------------------------------------------------------------

  static String encodeBackup(LibraryData data, String appVersion) {
    final payload = jsonEncode(data.toJson());
    return const JsonEncoder.withIndent('  ').convert({
      'format': backupFormat,
      'formatVersion': backupFormatVersion,
      'appVersion': appVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'entries': data.entries.length,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
  }

  /// Vérifie l'intégrité et décode une sauvegarde.
  static LibraryData decodeBackup(String text) {
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Ce fichier n\'est pas une sauvegarde Pazulu.');
    }
    if (json is! Map || json['format'] != backupFormat) {
      throw const FormatException('Ce fichier n\'est pas une sauvegarde Pazulu.');
    }
    final version = json['formatVersion'];
    if (version is! int || version > backupFormatVersion) {
      throw const FormatException(
        'Sauvegarde créée par une version plus récente de Pazulu.',
      );
    }
    final payload = json['payload'];
    if (payload is! String) {
      throw const FormatException('Sauvegarde incomplète.');
    }
    final hash = sha256.convert(utf8.encode(payload)).toString();
    if (hash != json['sha256']) {
      throw const FormatException(
        'Sauvegarde endommagée : la vérification d\'intégrité a échoué.',
      );
    }
    final inner = jsonDecode(payload);
    if (inner is! Map) throw const FormatException('Sauvegarde illisible.');
    return LibraryData.fromJson(inner.cast<String, dynamic>());
  }

  /// Fusionne une sauvegarde dans les données actuelles.
  /// Pour chaque œuvre, la version modifiée le plus récemment gagne ;
  /// les chapitres lus sont additionnés (jamais de perte de progression).
  static MergeReport merge(LibraryData current, LibraryData incoming) {
    current.activity.mergeFrom(incoming.activity);
    var added = 0;
    var updated = 0;
    for (final inc in incoming.entries.values) {
      final cur = current.entries[inc.work.id];
      if (cur == null) {
        current.entries[inc.work.id] = inc;
        added++;
        continue;
      }
      final readKeys = {...cur.progress.readKeys, ...inc.progress.readKeys};
      final mergedObservations = <String, List<String>>{};
      for (final bucket in {...cur.observedChapters.keys, ...inc.observedChapters.keys}) {
        final keys = <String>{
          ...?cur.observedChapters[bucket],
          ...?inc.observedChapters[bucket],
        }.toList();
        mergedObservations[bucket] = keys.length <= 1000
            ? keys : keys.sublist(keys.length - 1000);
      }
      final mergedSites = <String, SavedSiteLink>{};
      for (final link in [...cur.savedSiteLinks, ...inc.savedSiteLinks]) {
        mergedSites['${link.siteId}|${link.url}'] = link;
      }
      for (final key in {...cur.latestKnown.keys, ...inc.latestKnown.keys}) {
        final a = cur.latestKnown[key];
        final b = inc.latestKnown[key];
        if (b != null && (a == null || b > a)) cur.latestKnown[key] = b;
        if (a != null && (b == null || a > b)) inc.latestKnown[key] = a;
      }
      if (inc.updatedAt.isAfter(cur.updatedAt)) {
        inc.observedChapters = mergedObservations;
        inc.savedSiteLinks = mergedSites.values.toList();
        inc.progress.readKeys = readKeys;
        current.entries[inc.work.id] = inc;
        updated++;
      } else {
        cur.progress.readKeys = readKeys;
        cur.observedChapters = mergedObservations;
        cur.savedSiteLinks = mergedSites.values.toList();
      }
    }
    final known = current.updates.map((u) => u.id).toSet();
    for (final u in incoming.updates) {
      if (known.add(u.id)) current.updates.add(u);
    }
    current.updates.sort((a, b) => b.foundAt.compareTo(a.foundAt));
    return MergeReport(added: added, updated: updated);
  }
}

class MergeReport {
  const MergeReport({required this.added, required this.updated});

  final int added;
  final int updated;
}
