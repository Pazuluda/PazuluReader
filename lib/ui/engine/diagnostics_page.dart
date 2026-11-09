import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/source.dart';
import '../../design/theme.dart';
import '../../engine/diagnostics/connector_health.dart';
import '../../engine/diagnostics/source_status.dart';
import '../../engine/routing/circuit_breaker.dart';
import '../../extensions/manifest.dart';
import '../../extensions/registry.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Paramètres → Moteur Pazulu → Diagnostic des sources.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _testingAll = false;

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _test(String sourceId) async {
    final app = AppScope.read(context);
    try {
      final report = await app.testSource(sourceId);
      _notice('${report.sourceId} : ${report.status.code}'
          '${report.error == null ? '' : ' — ${report.error}'}');
    } on SourceException catch (e) {
      _notice(e.message);
    } catch (e) {
      _notice('Test impossible : $e');
    }
  }

  /// Sequential on purpose, with a pause: a diagnostic must not hammer sites.
  Future<void> _testAll() async {
    final app = AppScope.read(context);
    setState(() => _testingAll = true);
    try {
      for (final entry in app.diagnosticEntries()) {
        if (!mounted || entry.$3 == null) continue;
        await _test(entry.$1);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }

  Future<void> _export() async {
    final app = AppScope.read(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(app.exportEngineDiagnostics()));
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter le journal du moteur',
        fileName: 'pazulu-diagnostic-$date.json',
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _notice('Journal exporté (sans cookies, jetons ni chemins personnels).');
    } catch (e) {
      _notice('Export impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final entries = app.diagnosticEntries();
    final circuits = app.engine.breaker.all
        .where((c) => c.state != BreakerState.closed).toList();
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Diagnostic des sources'),
        actions: [
          TextButton.icon(
            onPressed: _testingAll ? null : _testAll,
            icon: _testingAll
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.playlist_play_rounded),
            label: const Text('Tester tout'),
          ),
          TextButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Exporter le journal'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(PazuluSpace.lg),
            children: [
              Text('« Lecture complète vérifiée » n\'apparaît qu\'après qu\'un chapitre '
                  'a réellement été chargé et ses images validées (test ou lecture). '
                  'Les tests sont manuels : quelques requêtes, jamais un aspirateur.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
              if (circuits.isNotEmpty) ...[
                const SizedBox(height: PazuluSpace.md),
                Glass(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Domaines en pause (circuit ouvert)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final c in circuits)
                        Text('${c.key} · ${c.reason ?? 'échecs répétés'}'
                            '${c.openUntil == null ? '' : ' · jusqu\'à ${_time(c.openUntil!)}'}',
                            style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: PazuluSpace.md),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: PazuluSpace.sm),
                  child: _SourceRow(
                    id: e.$1,
                    name: e.$2,
                    active: e.$3 != null,
                    ext: e.$4,
                    stats: app.connectorStats(e.$1),
                    testing: app.testingSources.contains(e.$1),
                    onTest: e.$3 == null ? null : () => _test(e.$1),
                  ),
                ),
              const SizedBox(height: PazuluSpace.lg),
              Text('Journal récent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final entry in app.engine.log.entries.reversed.take(40))
                Text('${_time(entry.at)} ${entry.level.name.toUpperCase()} '
                    '${entry.event}${entry.sourceId == null ? '' : ' [${entry.sourceId}]'}'
                    '${entry.message == null ? '' : ' — ${entry.message}'}'
                    '${entry.elapsedMs == null ? '' : ' (${entry.elapsedMs} ms)'}',
                    style: TextStyle(color: p.muted, fontSize: 11,
                        fontFamily: 'Consolas')),
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.id, required this.name, required this.active,
    required this.stats, required this.testing, this.ext, this.onTest});

  final String id;
  final String name;
  final bool active;
  final InstalledExtension? ext;
  final ConnectorStats stats;
  final bool testing;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final test = stats.lastTest;
    final status = test?.status ?? SourceStatus.unverified;
    final color = switch (status) {
      SourceStatus.fullReader => const Color(0xFF4ADE80),
      SourceStatus.partialReader => p.bright,
      SourceStatus.metadataOnly || SourceStatus.externalOnly => p.muted,
      SourceStatus.loginRequired || SourceStatus.subscriptionRequired ||
      SourceStatus.blocked => const Color(0xFFFBBF24),
      SourceStatus.broken => const Color(0xFFF87171),
      SourceStatus.unverified => p.muted,
    };
    String yesNo(bool? v) => v == null ? '—' : (v ? 'oui' : 'non');
    final latency = stats.avgLatencyMs;
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      ext == null
                          ? '$id · connecteur interne'
                          : '$id · ${ext!.manifest.id} ${ext!.manifest.version} · '
                              '${ext!.manifest.validation.code}',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Tag(status.code, color: color),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: testing || onTest == null ? null : onTest,
                icon: testing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined, size: 17),
                label: Text(active ? 'Tester cette source' : 'Désactivée'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _kv(p, 'État', status.label),
              _kv(p, 'Dernier succès', stats.lastSuccessAt == null
                  ? '—' : _DiagnosticsPageState._time(stats.lastSuccessAt!)),
              _kv(p, 'Temps de réponse', latency == null ? '—' : '${latency.round()} ms'),
              _kv(p, 'Recherche', yesNo(test?.searchOk)),
              _kv(p, 'Chapitres', test?.chaptersOk == null
                  ? '—' : '${yesNo(test?.chaptersOk)} (${test!.chapterCount})'),
              _kv(p, 'Pages lisibles', test?.pageSummary ?? yesNo(test?.pagesOk)),
              _kv(p, 'Fiabilité', '${(stats.reliability * 100).round()} % '
                  '(${stats.successes} ✓ / ${stats.failures} ✗)'),
            ],
          ),
          if ((test?.error ?? stats.lastError) != null) ...[
            const SizedBox(height: 6),
            Text('Dernière erreur : ${test?.error ?? stats.lastError}',
                style: const TextStyle(color: Color(0xFFF87171), fontSize: 12)),
          ],
          if (test != null && test.steps.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(test.steps.join('  ›  '),
                style: TextStyle(color: p.muted, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _kv(PazuluPalette p, String k, String v) => RichText(
        text: TextSpan(children: [
          TextSpan(text: '$k : ', style: TextStyle(color: p.muted, fontSize: 12)),
          TextSpan(text: v, style: TextStyle(color: p.text, fontSize: 12)),
        ]),
      );
}
