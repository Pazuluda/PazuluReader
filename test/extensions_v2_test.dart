import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/zip.dart';
import 'package:pazulu_reader/engine/engine_version.dart';
import 'package:pazulu_reader/extensions/manifest.dart';
import 'package:pazulu_reader/extensions/pack.dart';
import 'package:pazulu_reader/extensions/registry.dart';

Map<String, dynamic> base({String id = 'pazulu.demo', String version = '1.0.0'}) => {
      'schemaVersion': 2,
      'id': id,
      'name': 'Démo',
      'version': version,
      'languages': ['fr', 'en'],
      'contentTypes': ['manga', 'manhwa'],
      'hosts': ['demo.example'],
      'capabilities': {'search': true, 'chapters': true, 'pages': true},
      'transport': 'html',
      'paginationMode': 'auto',
      'minimumEngineVersion': '2.0.0',
      'html': {'family': 'madara'},
    };

ExtensionManifest m([Map<String, dynamic>? patch, String version = '1.0.0',
    String id = 'pazulu.demo']) =>
    ExtensionManifest.parse({...base(id: id, version: version), ...?patch});

LoadedPack packOf(List<ExtensionManifest> ms) => ExtensionPackReader.read(
    ExtensionPackReader.write(ms, publisher: 'Tests'), fileName: 'x.pazulupack');

void main() {
  group('Manifeste v2', () {
    test('exemple du cahier des charges accepté', () {
      final manifest = m();
      expect(manifest.id, 'pazulu.demo');
      expect(manifest.transport, ExtensionTransport.html);
      expect(manifest.html!.family, 'madara');
      expect(manifest.engineCompatible, isTrue);
      expect(manifest.validation, ValidationLevel.implementedUntested);
    });

    test('domaines dangereux, HTTP, IP et adaptateurs inconnus refusés', () {
      expect(() => m({'hosts': ['127.0.0.1']}), throwsFormatException);
      expect(() => m({'hosts': ['intranet.local']}), throwsFormatException);
      expect(() => m({'homeUrl': 'http://demo.example/'}), throwsFormatException);
      expect(() => m({'homeUrl': 'https://autre.example/'}), throwsFormatException);
      expect(() => m({'transport': 'native', 'nativeAdapter': 'evil'}), throwsFormatException);
      expect(() => m({'transport': 'javascript'}), throwsFormatException);
      expect(() => m({'html': {'family': 'madara', 'pageImages': ['<script>']}}),
          throwsFormatException);
      expect(() => m({'languages': ['klingon']}), throwsFormatException);
      expect(() => m({'rateLimit': {'requestsPerMinute': 100000}}), throwsFormatException);
    });

    test('version minimale du moteur respectée', () {
      final future = m({'minimumEngineVersion': '9.0.0'});
      expect(future.engineCompatible, isFalse);
      expect(SemVer.parse('2.0.0') > SemVer.parse('2.0.0-beta'), isTrue);
      expect(engineSatisfies('2.0.0'), isTrue);
    });

    test('les manifestes intégrés à l\'application sont valides', () {
      final index = jsonDecode(File('assets/extensions/index.json').readAsStringSync());
      final files = (index['files'] as List).cast<String>();
      expect(files, isNotEmpty);
      for (final f in files) {
        final manifest = ExtensionManifest.parse(File(f).readAsStringSync());
        expect(manifest.engineCompatible, isTrue, reason: f);
        // Untested declarative profiles must ship disabled.
        if (manifest.validation == ValidationLevel.implementedUntested) {
          expect(manifest.enabledByDefault, isFalse, reason: f);
        }
      }
    });
  });

  group('Packs', () {
    test('.pazulupack : écriture puis lecture avec empreintes SHA-256', () {
      final pack = packOf([m(), m(null, '1.0.0', 'pazulu.other')]);
      expect(pack.manifests.map((x) => x.id), ['pazulu.demo', 'pazulu.other']);
      expect(pack.verification.integrityOk, isTrue);
      expect(pack.verification.signed, isFalse);
      expect(pack.verification.publisher, 'Tests');
    });

    test('pack altéré : refusé', () {
      final good = ExtensionPackReader.write([m()]);
      final entries = readZip(good);
      final tampered = writeZip([
        for (final e in entries)
          e.name == 'pack.json'
              ? e
              : ZipEntry(e.name, Uint8List.fromList(utf8.encode(
                  utf8.decode(e.data).replaceAll('Démo', 'Piégé')))),
      ]);
      expect(() => ExtensionPackReader.read(tampered, fileName: 't.pazulupack'),
          throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('SHA-256'))));
    });

    test('chemin hors archive : refusé', () {
      final evil = writeZip([
        ZipEntry('pack.json', Uint8List.fromList(utf8.encode('{}'))),
        ZipEntry('../../evil.json', Uint8List.fromList(utf8.encode('{}'))),
      ]);
      expect(() => ExtensionPackReader.read(evil, fileName: 'e.pazulupack'),
          throwsFormatException);
    });

    test('.pazulusource : un manifeste JSON simple', () {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(base())));
      final pack = ExtensionPackReader.read(bytes, fileName: 'demo.pazulusource');
      expect(pack.manifests.single.id, 'pazulu.demo');
      expect(pack.verification.warnings, isNotEmpty);
    });
  });

  group('Registre (mise à jour atomique, retour arrière, désactivation)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pazulu-ext-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('installer, mettre à jour, revenir en arrière, désactiver, supprimer', () async {
      final registry = ExtensionRegistry(dir);
      await registry.load();
      final r1 = await registry.install(packOf([m()]));
      expect(r1.installed, ['pazulu.demo']);
      final r2 = await registry.install(packOf([m({'name': 'Démo v2'}, '1.1.0')]));
      expect(r2.updated, ['pazulu.demo']);
      expect(registry.byId('pazulu.demo')!.manifest.version, '1.1.0');
      expect(registry.byId('pazulu.demo')!.previousVersion, '1.0.0');

      // Persistence survives a restart.
      final reloaded = ExtensionRegistry(dir);
      await reloaded.load();
      expect(reloaded.byId('pazulu.demo')!.manifest.version, '1.1.0');

      expect(await reloaded.rollback('pazulu.demo'), isTrue);
      expect(reloaded.byId('pazulu.demo')!.manifest.version, '1.0.0');

      await reloaded.setEnabled('pazulu.demo', false);
      expect(reloaded.enabled, isEmpty);
      expect(await reloaded.remove('pazulu.demo'), isTrue);
      expect(reloaded.byId('pazulu.demo'), isNull);
    });

    test('version plus ancienne ou même version modifiée : refusées', () async {
      final registry = ExtensionRegistry(dir);
      await registry.load();
      await registry.install(packOf([m(null, '1.2.0')]));
      await expectLater(registry.install(packOf([m(null, '1.1.0')])), throwsFormatException);
      await expectLater(registry.install(packOf([m({'name': 'Autre'}, '1.2.0')])),
          throwsFormatException);
      final same = await registry.install(packOf([m(null, '1.2.0')]));
      expect(same.skipped, ['pazulu.demo']);
    });

    test('un pack invalide ne modifie rien (tout ou rien)', () async {
      final registry = ExtensionRegistry(dir);
      await registry.load();
      await registry.install(packOf([m()]));
      final mixed = LoadedPack(
        manifests: [m(null, '2.0.0'), m({'minimumEngineVersion': '9.0.0'}, '1.0.0', 'pazulu.future')],
        verification: const PackVerification(integrityOk: true, publisher: 't', signed: false),
        sha256: 'x',
      );
      await expectLater(registry.install(mixed), throwsFormatException);
      expect(registry.byId('pazulu.demo')!.manifest.version, '1.0.0');
      expect(registry.byId('pazulu.future'), isNull);
    });

    test('extension intégrée : désactivable et réinitialisable, jamais supprimée', () async {
      final bundled = m({'transport': 'native', 'nativeAdapter': 'mangadex',
          'enabledByDefault': true}, '2.0.0', 'pazulu.mangadex');
      final registry = ExtensionRegistry(dir, bundled: [bundled]);
      await registry.load();
      expect(registry.byId('pazulu.mangadex')!.enabled, isTrue);
      expect(registry.byId('pazulu.mangadex')!.origin, ExtensionOrigin.bundled);
      await registry.remove('pazulu.mangadex');
      expect(registry.byId('pazulu.mangadex'), isNotNull);
      expect(registry.byId('pazulu.mangadex')!.enabled, isFalse);
    });

    test('registre corrompu : conservé à part, valeurs par défaut utilisées', () async {
      File('${dir.path}${Platform.pathSeparator}registry.json').writeAsStringSync('{oups');
      final registry = ExtensionRegistry(dir);
      final problems = await registry.load();
      expect(problems, isNotEmpty);
      expect(dir.listSync().any((f) => f.path.contains('corrompu')), isTrue);
    });
  });
}
