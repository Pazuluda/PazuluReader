import 'dart:convert';
import 'dart:io';

import 'manifest.dart';
import 'pack.dart';

class InstalledExtension {
  const InstalledExtension({
    required this.manifest,
    required this.enabled,
    required this.origin,
    required this.installedAt,
    this.sha256,
    this.previousVersion,
    this.publisher = 'Pazulu',
    this.signed = false,
  });

  final ExtensionManifest manifest;
  final bool enabled;
  final ExtensionOrigin origin;
  final DateTime installedAt;
  final String? sha256;
  final String? previousVersion;
  final String publisher;
  final bool signed;

  String get id => manifest.id;

  InstalledExtension copyWith({bool? enabled, ExtensionManifest? manifest,
      String? previousVersion, bool clearPrevious = false, ExtensionOrigin? origin,
      String? sha256, DateTime? installedAt, String? publisher}) =>
      InstalledExtension(
        manifest: manifest ?? this.manifest,
        enabled: enabled ?? this.enabled,
        origin: origin ?? this.origin,
        installedAt: installedAt ?? this.installedAt,
        sha256: sha256 ?? this.sha256,
        previousVersion: clearPrevious ? null : (previousVersion ?? this.previousVersion),
        publisher: publisher ?? this.publisher,
        signed: signed,
      );

  Map<String, dynamic> toStateJson() => {
        'id': id,
        'version': manifest.version,
        'enabled': enabled,
        'origin': origin.name,
        'installedAt': installedAt.toIso8601String(),
        if (sha256 != null) 'sha256': sha256,
        if (previousVersion != null) 'previousVersion': previousVersion,
        'publisher': publisher,
      };
}

class InstallReport {
  const InstallReport({required this.installed, required this.updated,
    required this.skipped});
  final List<String> installed;
  final List<String> updated;
  final List<String> skipped;
}

/// Installed extensions, persisted under `<support>/extensions/`:
///
/// ```text
/// extensions/registry.json           état (version active, activée, origine)
/// extensions/<id>/<version>.json     manifeste exact de chaque version
/// ```
///
/// Installation is atomic: manifests are written first (tmp + rename), then
/// the registry is swapped (tmp + .bak + rename). A failure leaves the
/// previous state untouched. The previous version is kept for rollback.
/// Extensions never receive a path, a file handle or library data.
class ExtensionRegistry {
  ExtensionRegistry(this.root, {List<ExtensionManifest> bundled = const []})
      : _bundled = {for (final m in bundled) m.id: m};

  final Directory root;
  final Map<String, ExtensionManifest> _bundled;
  final Map<String, InstalledExtension> _items = {};

  String get _sep => Platform.pathSeparator;
  File get _registryFile => File('${root.path}${_sep}registry.json');

  List<InstalledExtension> get all {
    final list = _items.values.toList()
      ..sort((a, b) => a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return List.unmodifiable(list);
  }

  Iterable<InstalledExtension> get enabled => _items.values.where((e) =>
      e.enabled && e.manifest.engineCompatible);

  InstalledExtension? byId(String id) => _items[id];

  /// Loads bundled manifests, then applies the persisted state. A corrupt
  /// registry is kept aside (never deleted) and bundled defaults are used.
  Future<List<String>> load() async {
    final problems = <String>[];
    _items.clear();
    for (final m in _bundled.values) {
      _items[m.id] = InstalledExtension(manifest: m, enabled: m.enabledByDefault,
          origin: ExtensionOrigin.bundled, installedAt: DateTime.fromMillisecondsSinceEpoch(0),
          publisher: 'Pazulu (intégrée)', signed: true);
    }
    if (!await _registryFile.exists()) return problems;
    Object? state;
    try {
      state = jsonDecode(await _registryFile.readAsString());
    } catch (_) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await _registryFile.copy('${_registryFile.path}.corrompu.$stamp');
      problems.add('Registre des extensions illisible, copie conservée.');
      return problems;
    }
    if (state is! Map || state['format'] != 'pazulu-extensions' || state['items'] is! List) {
      problems.add('Registre des extensions au format inconnu.');
      return problems;
    }
    for (final raw in state['items'] as List) {
      if (raw is! Map || raw['id'] is! String || raw['version'] is! String) continue;
      final id = raw['id'] as String;
      final version = raw['version'] as String;
      final origin = raw['origin'] == 'userFile' ? ExtensionOrigin.userFile : ExtensionOrigin.bundled;
      ExtensionManifest? manifest;
      final bundled = _bundled[id];
      if (bundled != null && bundled.version == version) {
        manifest = bundled;
      } else {
        try {
          manifest = ExtensionManifest.parse(await _versionFile(id, version).readAsString());
          if (manifest.id != id) manifest = null;
        } catch (e) {
          problems.add('Extension $id $version illisible : $e');
          manifest = null;
        }
      }
      if (manifest == null) continue;
      // A bundled update shipped with a newer app wins over an older copy.
      if (bundled != null && origin == ExtensionOrigin.bundled &&
          bundled.semver > manifest.semver) {
        manifest = bundled;
      }
      _items[id] = InstalledExtension(
        manifest: manifest,
        enabled: raw['enabled'] != false,
        origin: origin,
        installedAt: DateTime.tryParse('${raw['installedAt']}') ?? DateTime.now(),
        sha256: raw['sha256'] is String ? raw['sha256'] as String : null,
        previousVersion: raw['previousVersion'] is String ? raw['previousVersion'] as String : null,
        publisher: raw['publisher'] is String ? raw['publisher'] as String : 'Inconnu',
        signed: origin == ExtensionOrigin.bundled,
      );
    }
    return problems;
  }

  File _versionFile(String id, String version) =>
      File('${root.path}$_sep$id$_sep$version.json');

  /// Validates every manifest of the pack BEFORE writing anything.
  Future<InstallReport> install(LoadedPack pack, {bool enable = true}) async {
    final installed = <String>[];
    final updated = <String>[];
    final skipped = <String>[];
    final staged = Map<String, InstalledExtension>.of(_items);
    final toWrite = <ExtensionManifest>[];
    for (final m in pack.manifests) {
      if (!m.engineCompatible) {
        throw FormatException('${m.name} demande le moteur ${m.minimumEngineVersion} '
            'ou plus récent.');
      }
      final current = staged[m.id];
      if (current != null) {
        final cmp = m.semver.compareTo(current.manifest.semver);
        if (cmp < 0) {
          throw FormatException('${m.name} ${m.version} est plus ancienne que la '
              'version installée ${current.manifest.version}. Utilisez « Revenir '
              'à la version précédente ».');
        }
        if (cmp == 0) {
          final same = jsonEncode(m.toJson()) == jsonEncode(current.manifest.toJson());
          if (!same) {
            throw FormatException('${m.name} ${m.version} existe déjà avec un '
                'contenu différent : la version doit être incrémentée.');
          }
          skipped.add(m.id);
          continue;
        }
        staged[m.id] = current.copyWith(
          manifest: m,
          enabled: enable ? true : current.enabled,
          origin: ExtensionOrigin.userFile,
          previousVersion: current.manifest.version,
          sha256: pack.sha256,
          installedAt: DateTime.now(),
          publisher: pack.verification.publisher,
        );
        updated.add(m.id);
      } else {
        staged[m.id] = InstalledExtension(
          manifest: m,
          enabled: enable,
          origin: ExtensionOrigin.userFile,
          installedAt: DateTime.now(),
          sha256: pack.sha256,
          publisher: pack.verification.publisher,
        );
        installed.add(m.id);
      }
      toWrite.add(m);
    }
    // Keep the outgoing versions on disk so rollback always has a file.
    for (final m in toWrite) {
      final previous = _items[m.id];
      if (previous != null && _bundled[m.id]?.version != previous.manifest.version) {
        await _writeManifest(previous.manifest);
      }
      await _writeManifest(m);
    }
    await _saveState(staged);
    _items
      ..clear()
      ..addAll(staged);
    return InstallReport(installed: installed, updated: updated, skipped: skipped);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final item = _items[id];
    if (item == null) return;
    final staged = Map<String, InstalledExtension>.of(_items);
    staged[id] = item.copyWith(enabled: enabled);
    await _saveState(staged);
    _items[id] = staged[id]!;
  }

  /// Returns to the previous version (user update or bundled original).
  Future<bool> rollback(String id) async {
    final item = _items[id];
    final previous = item?.previousVersion;
    if (item == null || previous == null) return false;
    ExtensionManifest manifest;
    final bundled = _bundled[id];
    if (bundled != null && bundled.version == previous) {
      manifest = bundled;
    } else {
      final file = _versionFile(id, previous);
      if (!await file.exists()) return false;
      manifest = ExtensionManifest.parse(await file.readAsString());
    }
    final staged = Map<String, InstalledExtension>.of(_items);
    staged[id] = item.copyWith(
      manifest: manifest,
      clearPrevious: true,
      origin: bundled != null && bundled.version == previous
          ? ExtensionOrigin.bundled : item.origin,
      installedAt: DateTime.now(),
    );
    await _saveState(staged);
    _items[id] = staged[id]!;
    return true;
  }

  /// User extensions are removed; bundled ones can only be disabled or
  /// returned to their bundled version.
  Future<bool> remove(String id) async {
    final item = _items[id];
    if (item == null) return false;
    final bundled = _bundled[id];
    final staged = Map<String, InstalledExtension>.of(_items);
    if (bundled != null) {
      staged[id] = InstalledExtension(manifest: bundled, enabled: false,
          origin: ExtensionOrigin.bundled, installedAt: DateTime.now(),
          publisher: 'Pazulu (intégrée)', signed: true);
    } else {
      staged.remove(id);
    }
    await _saveState(staged);
    _items
      ..clear()
      ..addAll(staged);
    return true;
  }

  Future<void> _writeManifest(ExtensionManifest m) async {
    final file = _versionFile(m.id, m.version);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(m.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<void> _saveState(Map<String, InstalledExtension> items) async {
    await root.create(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert({
      'format': 'pazulu-extensions',
      'schemaVersion': 1,
      'items': items.values.map((e) => e.toStateJson()).toList(),
    });
    final tmp = File('${_registryFile.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    if (await _registryFile.exists()) {
      await _registryFile.copy('${_registryFile.path}.bak');
      await _registryFile.delete();
    }
    await tmp.rename(_registryFile.path);
  }
}
