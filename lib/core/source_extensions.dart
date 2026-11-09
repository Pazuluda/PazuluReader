import 'dart:convert';
import 'dart:io';

import 'source_catalog.dart';

/// A source adapter is DATA, not executable third-party code. The common engine
/// uses these selectors in a browser that the user has already opened.
/// No remote JS, no browser profile access, no automatic DRM/access bypass.
class SourceRecipe {
  const SourceRecipe({
    required this.id,
    required this.version,
    required this.mode,
    required this.selectors,
    this.minimumWidth = 360,
    this.minimumHeight = 450,
    this.hostAliases = const [],
    this.homeOverride,
  });

  final String id;
  final int version;
  /// native = API connector, inspect = DOM inspection with user action,
  /// official = only the site's own viewing experience.
  final String mode;
  final List<String> selectors;
  final int minimumWidth;
  final int minimumHeight;
  final List<String> hostAliases;
  final String? homeOverride;

  bool accepts(CatalogSite site, String url) {
    if (site.accepts(url)) return true;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasPort || uri.host.isEmpty) return false;
    final hostname = uri.host.toLowerCase();
    return hostAliases.any((h) => hostname == h || hostname.endsWith('.$h'));
  }

  bool get canInspect => mode == 'inspect';

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'mode': mode,
        'selectors': selectors,
        'minimumWidth': minimumWidth,
        'minimumHeight': minimumHeight,
        'hostAliases': hostAliases,
        'homeOverride': homeOverride,
      };

  factory SourceRecipe.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final version = value['version'];
    final mode = value['mode'];
    final selectors = value['selectors'];
    final minWidth = value['minimumWidth'] ?? 360;
    final minHeight = value['minimumHeight'] ?? 450;
    final aliases = value['hostAliases'] ?? const [];
    final homeOverride = value['homeOverride'];
    if (id is! String || catalogSiteById(id) == null ||
        version is! int || version < 1 || version > 1000000 ||
        mode is! String || !const ['native', 'inspect', 'official'].contains(mode) ||
        selectors is! List || selectors.length > 20 ||
        selectors.any((s) => s is! String || s.length > 180 ||
            s.contains('<') || s.contains('>') || s.contains('\\') ||
            s.contains('{') || s.contains('}')) ||
        minWidth is! int || minWidth < 100 || minWidth > 3000 ||
        minHeight is! int || minHeight < 100 || minHeight > 3000 ||
        aliases is! List || aliases.length > 3 ||
        aliases.any((h) => h is! String || h.length > 253 ||
            (!RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(h) ||
             h.endsWith('.local') || h.endsWith('.localhost') ||
             RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(h))) ||
        (homeOverride != null && homeOverride is! String)) {
      throw const FormatException('Profil de source invalide.');
    }
    // An imported JSON manifest may not turn official/native-only sources into
    // an extraction rule without a vetted application update.
    final initial = SourceRecipeRegistry.bundled[id]!;
    if (initial.mode != 'inspect' && mode != initial.mode) {
      throw const FormatException('La politique de cette source est verrouillee.');
    }
    final site = catalogSiteById(id)!;
    if (homeOverride != null && homeOverride.isNotEmpty &&
        !((Uri.tryParse(homeOverride)?.scheme == 'https') &&
          (site.accepts(homeOverride) || aliases.contains(Uri.parse(homeOverride).host)) &&
          Uri.parse(homeOverride).userInfo.isEmpty && !Uri.parse(homeOverride).hasPort)) {
      throw const FormatException('Adresse de source non autorisee.');
    }
    if (initial.mode != 'inspect' && (aliases.isNotEmpty || homeOverride != null)) {
      throw const FormatException('Le domaine d’une source officielle est verrouille.');
    }
    if (mode == 'inspect' && selectors.isEmpty) {
      throw const FormatException('Les selecteurs sont manquants.');
    }
    return SourceRecipe(
      id: id, version: version, mode: mode,
      selectors: List<String>.unmodifiable(selectors.cast<String>()),
      minimumWidth: minWidth, minimumHeight: minHeight,
      hostAliases: List<String>.unmodifiable(aliases.cast<String>()),
      homeOverride: homeOverride as String?,
    );
  }
}

class SourceRecipeRegistry {
  SourceRecipeRegistry._(this._recipes);

  /// Common selectors shared by sources that publish ordinary HTML page images.
  /// Unverified: pages built with JS, canvas, authentication, or special image
  /// protocols may not be detectable. The user must explicitly run inspection.
  static const commonSelectors = <String>[
    '.reading-content img', '#readerarea img', '#chapter-content img',
    '.chapter-content img', '.page-break img', '.chapter-images img',
    '.reader-area img', '.reader img', '#viewer img',
    'main img', 'article img',
  ];

  static const Map<String, SourceRecipe> bundled = {
    'manhuafast': SourceRecipe(id: 'manhuafast', version: 1, mode: 'inspect', selectors: commonSelectors),
    'manhuaus': SourceRecipe(id: 'manhuaus', version: 1, mode: 'inspect', selectors: commonSelectors),
    'asurascans': SourceRecipe(id: 'asurascans', version: 1, mode: 'inspect', selectors: [
      '.reading-content img', '#readerarea img', '.chapter-images img', ...commonSelectors,
    ]),
    'aethonwebcomics': SourceRecipe(id: 'aethonwebcomics', version: 1, mode: 'official', selectors: []),
    'manhwaclan': SourceRecipe(id: 'manhwaclan', version: 1, mode: 'inspect', selectors: commonSelectors),
    'scanmanga': SourceRecipe(id: 'scanmanga', version: 1, mode: 'inspect', selectors: commonSelectors),
    'thunderscans': SourceRecipe(id: 'thunderscans', version: 1, mode: 'inspect', selectors: commonSelectors),
    'toongod': SourceRecipe(id: 'toongod', version: 1, mode: 'inspect', selectors: commonSelectors),
    'swordhound': SourceRecipe(id: 'swordhound', version: 1, mode: 'inspect', selectors: commonSelectors),
    'sssclasshunter': SourceRecipe(id: 'sssclasshunter', version: 1, mode: 'inspect', selectors: commonSelectors),
    'manhuatop': SourceRecipe(id: 'manhuatop', version: 1, mode: 'inspect', selectors: commonSelectors),
    'mangadex': SourceRecipe(id: 'mangadex', version: 1, mode: 'native', selectors: []),
    'kingofshojo': SourceRecipe(id: 'kingofshojo', version: 1, mode: 'inspect', selectors: commonSelectors),
    'webtoon_fr': SourceRecipe(id: 'webtoon_fr', version: 1, mode: 'official', selectors: []),
    'webtoon_en': SourceRecipe(id: 'webtoon_en', version: 1, mode: 'official', selectors: []),
  };

  factory SourceRecipeRegistry.defaults() =>
      SourceRecipeRegistry._(Map<String, SourceRecipe>.of(bundled));

  final Map<String, SourceRecipe> _recipes;
  SourceRecipe forSite(String id) => _recipes[id] ?? bundled[id] ??
      SourceRecipe(
        id: id, version: 1, mode: 'inspect', selectors: commonSelectors,
      );
  Iterable<SourceRecipe> get all => _recipes.values;

  /// Apply a complete or partial update atomically. Old, invalid, or unknown
  /// source definitions do not partially overwrite any current definitions.
  /// Updates only alter selectors/mode/thresholds, NEVER code or permitted hosts.
  int mergeManifest(String jsonText) {
    final json = jsonDecode(jsonText);
    if (json is! Map || json['format'] != 'pazulu-source-recipes' ||
        json['schemaVersion'] != 1 || json['recipes'] is! List) {
      throw const FormatException('Format du pack de sources non reconnu.');
    }
    final incoming = json['recipes'] as List;
    if (incoming.length > bundled.length) {
      throw const FormatException('Trop de profils dans le pack.');
    }
    final staged = Map<String, SourceRecipe>.of(_recipes);
    final ids = <String>{};
    var changed = 0;
    for (final raw in incoming) {
      if (raw is! Map) throw const FormatException('Profil de source incomplet.');
      final recipe = SourceRecipe.fromJson(raw.cast<String, dynamic>());
      if (!ids.add(recipe.id)) throw const FormatException('Identifiant de source duplique.');
      if (recipe.version < staged[recipe.id]!.version) {
        throw const FormatException('Ce pack contient un ancien profil.');
      }
      staged[recipe.id] = recipe;
      changed++;
    }
    _recipes..clear()..addAll(staged);
    return changed;
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'format': 'pazulu-source-recipes',
        'schemaVersion': 1,
        'recipes': all.map((r) => r.toJson()).toList(),
      });
}

class SourceRecipeStore {
  SourceRecipeStore(this.file);
  final File file;

  Future<SourceRecipeRegistry> load() async {
    final registry = SourceRecipeRegistry.defaults();
    if (!await file.exists()) return registry;
    try {
      registry.mergeManifest(await file.readAsString());
    } catch (_) {
      // Old configuration stays available for diagnosis; never delete it.
      return SourceRecipeRegistry.defaults();
    }
    return registry;
  }

  Future<void> save(SourceRecipeRegistry registry) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(registry.exportJson(), flush: true);
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}
