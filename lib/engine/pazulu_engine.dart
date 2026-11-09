import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http_pkg;

import '../core/models.dart';
import '../core/source.dart';
import '../extensions/manifest.dart';
import '../extensions/pack.dart';
import '../extensions/registry.dart';
import '../extensions/runtime/declarative_source.dart';
import 'availability.dart';
import 'diagnostics/connector_health.dart';
import 'diagnostics/engine_log.dart';
import 'diagnostics/source_status.dart';
import 'diagnostics/source_test_runner.dart';
import 'discovery/discovery_engine.dart';
import 'engine_version.dart';
import 'http/engine_http.dart';
import 'routing/chapter_resolver.dart';
import 'routing/circuit_breaker.dart';
import 'routing/smart_router.dart';

/// Pazulu Source Engine 2.0 — independent from the widgets.
///
/// Owns the safe HTTP client, circuit breaker, page validation, the Smart
/// Source Router, the discovery engine, the extension registry and the
/// diagnostics. AppState keeps the library; the engine never reads or writes
/// personal data (library, progress, profiles).
class PazuluEngine {
  PazuluEngine({http_pkg.Client? client, HostResolver? resolver, bool checkDns = true})
      : log = EngineLog(),
        breaker = CircuitBreaker(),
        health = ConnectorHealthStore() {
    http = EngineHttpClient(client: client, resolver: resolver, breaker: breaker,
        log: log, checkDns: checkDns);
    chapterResolver = ChapterResolver(http: http, log: log);
    router = SmartSourceRouter(resolver: chapterResolver, breaker: breaker, health: health);
    ranker = SourceRanker(health);
    discovery = DiscoveryEngine(log: log);
    tests = SourceTestRunner(resolver: chapterResolver, log: log);
  }

  static const String version = pazuluEngineVersion;

  final EngineLog log;
  final CircuitBreaker breaker;
  final ConnectorHealthStore health;
  late final EngineHttpClient http;
  late final ChapterResolver chapterResolver;
  late final SmartSourceRouter router;
  late final SourceRanker ranker;
  late final DiscoveryEngine discovery;
  late final SourceTestRunner tests;
  ExtensionRegistry? _extensions;

  ExtensionRegistry? get extensions => _extensions;

  /// Loads persisted health and installed extensions. [bundledManifests] are
  /// the JSON texts shipped in the application's assets.
  Future<List<String>> init(Directory supportDir, List<String> bundledManifests) async {
    final sep = Platform.pathSeparator;
    health.file = File('${supportDir.path}${sep}engine${sep}connector-health.json');
    await health.load();
    final problems = <String>[];
    final bundled = <ExtensionManifest>[];
    for (final text in bundledManifests) {
      try {
        bundled.add(ExtensionManifest.parse(text));
      } catch (e) {
        problems.add('Extension intégrée invalide : $e');
      }
    }
    final registry = ExtensionRegistry(
        Directory('${supportDir.path}${sep}extensions'), bundled: bundled);
    problems.addAll(await registry.load());
    _extensions = registry;
    for (final p in problems) {
      log.warn('extensions', message: p);
    }
    log.info('engine_ready', message: 'Moteur Pazulu $version, '
        '${registry.all.length} extension(s)');
    return problems;
  }

  /// Declarative (Level 1) sources for every enabled, compatible extension.
  List<ContentSource> buildDeclarativeSources() {
    final registry = _extensions;
    if (registry == null) return const [];
    return [
      for (final e in registry.enabled)
        if (e.manifest.transport != ExtensionTransport.native)
          DeclarativeHtmlSource(e.manifest, http),
    ];
  }

  /// Whether a compiled adapter is enabled (manifest present and active).
  bool nativeEnabled(String adapterId) {
    final registry = _extensions;
    if (registry == null) return true;
    final manifests = registry.all.where((e) => e.manifest.nativeAdapter == adapterId);
    if (manifests.isEmpty) return true; // no manifest = always-on core adapter
    return manifests.any((e) => e.enabled);
  }

  InstalledExtension? extensionForSource(String sourceId) {
    final registry = _extensions;
    if (registry == null) return null;
    for (final e in registry.all) {
      if (e.manifest.id == sourceId || e.manifest.nativeAdapter == sourceId) return e;
    }
    return null;
  }

  LoadedPack readPack(Uint8List bytes, String fileName) =>
      ExtensionPackReader.read(bytes, fileName: fileName);

  Future<void> saveHealth() => health.save();

  /// Records a reader outcome (including WebView2 captures) so diagnostics
  /// can show a real FULL_READER only after a validated chapter.
  void recordReaderOutcome(SourceChapter chapter, ChapterPages pages) {
    final stats = health.of(chapter.sourceId);
    if (pages.readable) {
      stats.recordSuccess(pages.elapsed ?? Duration.zero);
      final status = pages.completeness == PageCompleteness.complete
          ? SourceStatus.fullReader : SourceStatus.partialReader;
      final previous = stats.lastTest;
      if (previous == null || previous.status != SourceStatus.fullReader ||
          status == SourceStatus.fullReader) {
        stats.lastTest = SourceTestReport(sourceId: chapter.sourceId, at: DateTime.now(),
            status: status, pagesOk: true, pageSummary: pages.summary,
            steps: ['Validé à la lecture du ${chapter.key.longLabel} (${chapter.lang}).']);
      }
    } else {
      stats.recordFailure(pages.summary);
    }
  }

  Future<SourceTestReport> testSource(ContentSource source, {
    required List<String> languages,
  }) async {
    final ext = extensionForSource(source.id);
    String? query;
    String? workUrl;
    for (final t in ext?.manifest.tests ?? const <ExtensionTest>[]) {
      query ??= t.query;
      workUrl ??= t.workUrl;
    }
    final report = await tests.run(source,
        query: query ?? defaultTestQuery(source),
        languages: languages, workId: workUrl);
    health.of(source.id).lastTest = report;
    await health.save().catchError((Object _) {});
    return report;
  }

  /// Diagnostics export: journal + connector stats + circuits. Already
  /// redacted (no cookies, tokens, signed URLs or personal paths).
  String exportDiagnostics() => const JsonEncoder.withIndent('  ').convert({
        'format': 'pazulu-engine-diagnostics',
        'engineVersion': version,
        'exportedAt': DateTime.now().toIso8601String(),
        'connectors': health.stats.values.map((s) => s.toJson()).toList(),
        'circuits': [
          for (final c in breaker.all)
            {
              'host': c.key,
              'state': c.state.name,
              'openUntil': c.openUntil?.toIso8601String(),
              'reason': c.reason,
            },
        ],
        'log': jsonDecode(log.exportJson()),
      });

  void dispose() => http.close();
}
