import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/zip.dart';
import 'manifest.dart';

/// Origin of an installed extension.
enum ExtensionOrigin {
  /// Shipped inside the signed application build.
  bundled,

  /// Imported by the user from a .pazulusource / .pazulupack file.
  userFile,
}

/// Integrity / origin report shown before installation.
class PackVerification {
  const PackVerification({
    required this.integrityOk,
    required this.publisher,
    required this.signed,
    this.warnings = const [],
  });

  /// Every file hash declared in the pack matched.
  final bool integrityOk;
  final String publisher;

  /// True only if a signature was cryptographically verified. Pazulu 2.0
  /// does not ship an asymmetric verifier yet (see docs), so user packs are
  /// reported as unsigned and require an explicit confirmation.
  final bool signed;
  final List<String> warnings;
}

class LoadedPack {
  const LoadedPack({required this.manifests, required this.verification,
    required this.sha256, this.name});

  final List<ExtensionManifest> manifests;
  final PackVerification verification;

  /// SHA-256 of the whole file, recorded with the installation.
  final String sha256;
  final String? name;
}

/// Reader for `.pazulusource` (one manifest, JSON) and `.pazulupack`
/// (ZIP with `pack.json` + manifests, each listed with its SHA-256).
///
/// Nothing in a pack is executed. Unknown files are ignored, paths are
/// confined to the archive, sizes are bounded.
class ExtensionPackReader {
  const ExtensionPackReader._();

  static const int maxPackBytes = 4 * 1024 * 1024;
  static const int maxSources = 64;

  static LoadedPack read(Uint8List bytes, {required String fileName}) {
    if (bytes.length > maxPackBytes) {
      throw const FormatException('Pack trop volumineux (4 Mo maximum).');
    }
    final digest = sha256.convert(bytes).toString();
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pazulusource') || lower.endsWith('.json')) {
      final text = utf8.decode(bytes, allowMalformed: false);
      final manifest = ExtensionManifest.parse(text);
      return LoadedPack(
        manifests: [manifest],
        sha256: digest,
        verification: const PackVerification(
          integrityOk: true,
          publisher: 'Fichier local',
          signed: false,
          warnings: ['Extension non signée : installez-la seulement si vous '
              'connaissez son auteur.'],
        ),
      );
    }
    if (!lower.endsWith('.pazulupack') && !lower.endsWith('.zip')) {
      throw const FormatException('Format attendu : .pazulusource ou .pazulupack');
    }
    final entries = readZip(bytes);
    final files = <String, Uint8List>{};
    for (final e in entries) {
      final name = e.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains('../') || name.contains(':')) {
        throw const FormatException('Chemin interdit dans le pack.');
      }
      files[name] = e.data;
    }
    final indexBytes = files['pack.json'];
    if (indexBytes == null) throw const FormatException('pack.json manquant.');
    final index = jsonDecode(utf8.decode(indexBytes));
    if (index is! Map || index['format'] != 'pazulu-pack' ||
        index['schemaVersion'] != 1 || index['sources'] is! List) {
      throw const FormatException('pack.json invalide (format pazulu-pack v1).');
    }
    final listed = index['sources'] as List;
    if (listed.isEmpty || listed.length > maxSources) {
      throw const FormatException('Nombre de sources du pack invalide.');
    }
    final manifests = <ExtensionManifest>[];
    final ids = <String>{};
    var integrity = true;
    final warnings = <String>[];
    for (final item in listed) {
      if (item is! Map || item['path'] is! String || item['sha256'] is! String) {
        throw const FormatException('Entrée de pack incomplète (path, sha256).');
      }
      final path = item['path'] as String;
      final data = files[path];
      if (data == null) throw FormatException('Fichier absent du pack : $path');
      final actual = sha256.convert(data).toString();
      if (actual != (item['sha256'] as String).toLowerCase()) {
        integrity = false;
        throw FormatException('Empreinte SHA-256 incorrecte pour $path : '
            'pack altéré ou incomplet.');
      }
      final manifest = ExtensionManifest.parse(utf8.decode(data));
      if (!ids.add(manifest.id)) {
        throw FormatException('Identifiant en double : ${manifest.id}');
      }
      manifests.add(manifest);
    }
    final publisher = index['publisher'] is String ? index['publisher'] as String : 'Inconnu';
    if (index['signature'] != null) {
      warnings.add('Le pack contient une signature, mais cette version de '
          'Pazulu ne sait pas encore la vérifier : elle est ignorée.');
    }
    warnings.add('Pack non signé vérifiable : intégrité interne contrôlée '
        '(SHA-256), origine déclarée « $publisher » non prouvée.');
    return LoadedPack(
      manifests: manifests,
      sha256: digest,
      name: index['name'] is String ? index['name'] as String : null,
      verification: PackVerification(
        integrityOk: integrity,
        publisher: publisher,
        signed: false,
        warnings: warnings,
      ),
    );
  }

  /// Builds a .pazulupack (used by tests and by "export" in the UI).
  static Uint8List write(List<ExtensionManifest> manifests,
      {String name = 'Pack Pazulu', String publisher = 'Utilisateur'}) {
    final entries = <ZipEntry>[];
    final listed = <Map<String, String>>[];
    for (final m in manifests) {
      final data = Uint8List.fromList(utf8.encode(
          const JsonEncoder.withIndent('  ').convert(m.toJson())));
      final path = 'sources/${m.id}.json';
      entries.add(ZipEntry(path, data));
      listed.add({'path': path, 'sha256': sha256.convert(data).toString()});
    }
    final index = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'format': 'pazulu-pack',
      'schemaVersion': 1,
      'name': name,
      'publisher': publisher,
      'sources': listed,
    })));
    return writeZip([ZipEntry('pack.json', index), ...entries]);
  }
}
