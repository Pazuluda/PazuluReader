import 'dart:convert';
import 'dart:io';

import 'source_catalog.dart';

/// Only publicly named HTTPS web sites can be registered; no local network
/// targets, credentials, custom ports or executable extensions are accepted.
Uri normalizedSourceUri(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasPort ||
      uri.host.contains(':') || uri.host.length > 253 ||
      uri.host.endsWith('.local') || uri.host.endsWith('.localhost') ||
      !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$', caseSensitive: false)
          .hasMatch(uri.host) ||
      RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(uri.host) ||
      uri.host == 'localhost' || uri.host.endsWith('.internal') ||
      uri.host.endsWith('.test') || uri.host.endsWith('.example') ||
      uri.host.endsWith('.invalid') ||
      uri.pathSegments.any((s) => s == '..' || s == '.')) {
    throw const FormatException('Saisis une URL HTTPS publique (sans port ni identifiants).');
  }
  return Uri(scheme: 'https', host: uri.host, path: uri.path);
}

class UserSource {
  const UserSource({
    required this.id,
    required this.name,
    required this.url,
    required this.languages,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String url;
  final List<String> languages;
  final bool enabled;

  CatalogSite toCatalogSite() => CatalogSite(
      id, name, url, languages, SiteIntegration.website);

  UserSource withEnabled(bool active) => UserSource(
      id: id, name: name, url: url, languages: languages, enabled: active);

  /// Keep the same ID when a personal site changes its domain. Existing works
  /// stay linked to that source, but old saved URLs are not rewritten silently.
  UserSource withDetails({
    required String url,
    required String name,
    required List<String> languages,
  }) => UserSource.fromJson({
        'id': id,
        'name': name,
        'url': normalizedSourceUri(url).toString(),
        'languages': languages,
        'enabled': enabled,
      });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'url': url, 'languages': languages, 'enabled': enabled,
  };

  factory UserSource.fromJson(Map<String, dynamic> raw) {
    final id = raw['id'];
    final name = raw['name'];
    final url = raw['url'];
    final languages = raw['languages'];
    final enabled = raw['enabled'] ?? true;
    if (id is! String ||
        !RegExp(r'^user_[a-z0-9_]{5,80}$').hasMatch(id) ||
        name is! String || name.trim().isEmpty || name.length > 90 ||
        url is! String || url.length > 2048 ||
        languages is! List || languages.isEmpty || languages.length > 2 ||
        languages.any((l) => l != 'fr' && l != 'en') ||
        languages.toSet().length != languages.length ||
        enabled is! bool) {
      throw const FormatException('Source personnalisee invalide.');
    }
    final clean = normalizedSourceUri(url).toString();
    return UserSource(
      id: id, name: name.trim(), url: clean,
      languages: List<String>.unmodifiable(languages.cast<String>()),
      enabled: enabled,
    );
  }
}

/// Persistence is independent of library.json: adding/disabling a site cannot
/// modify existing reading progress, downloads or library backup snapshots.
class UserSourceStore {
  UserSourceStore(this.file);
  final File file;

  static const maxSources = 250;

  static List<UserSource> decode(String text) {
    if (text.length > 160000) throw const FormatException('Catalogue trop volumineux.');
    final raw = jsonDecode(text);
    if (raw is! Map || raw['format'] != 'pazulu-user-sources' ||
        raw['schemaVersion'] != 1 || raw['sources'] is! List ||
        (raw['sources'] as List).length > maxSources) {
      throw const FormatException('Format du catalogue non reconnu.');
    }
    final sources = <UserSource>[];
    final ids = <String>{};
    final urls = <String>{};
    for (final item in raw['sources'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Element de catalogue incorrect.');
      }
      final source = UserSource.fromJson(item);
      if (!ids.add(source.id) || !urls.add(source.url)) {
        throw const FormatException('Source dupliquee.');
      }
      sources.add(source);
    }
    return sources;
  }

  static String encode(Iterable<UserSource> sources) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'pazulu-user-sources',
        'schemaVersion': 1,
        'sources': sources.map((s) => s.toJson()).toList(),
      });

  Future<List<UserSource>> load() async {
    if (!await file.exists()) return [];
    return decode(await file.readAsString());
  }

  Future<void> save(Iterable<UserSource> sources) async {
    final text = encode(sources);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(text, flush: true);
    if (await file.exists()) await file.copy('${file.path}.bak');
    // Keep a valid previous file even if the tmp write failed.
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

UserSource createUserSource({
  required String url,
  String name = '',
  List<String> languages = const ['fr', 'en'],
  String? id,
}) {
  final uri = normalizedSourceUri(url);
  final suggested = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final now = DateTime.now().microsecondsSinceEpoch;
  return UserSource.fromJson({
    'id': id ?? 'user_${now}_site',
    'name': name.trim().isEmpty ? suggested : name.trim(),
    'url': uri.toString(),
    'languages': languages,
    'enabled': true,
  });
}
