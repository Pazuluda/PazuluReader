import 'dart:convert';
import 'dart:io';

import 'source_status.dart';

/// One "Tester cette source" run.
class SourceTestReport {
  const SourceTestReport({
    required this.sourceId,
    required this.at,
    required this.status,
    this.searchOk,
    this.searchCount = 0,
    this.searchMs,
    this.chaptersOk,
    this.chapterCount = 0,
    this.pagesOk,
    this.pageSummary,
    this.totalMs,
    this.error,
    this.steps = const [],
  });

  final String sourceId;
  final DateTime at;
  final SourceStatus status;
  final bool? searchOk;
  final int searchCount;
  final int? searchMs;
  final bool? chaptersOk;
  final int chapterCount;
  final bool? pagesOk;
  final String? pageSummary;
  final int? totalMs;
  final String? error;
  final List<String> steps;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'at': at.toIso8601String(),
        'status': status.code,
        'searchOk': searchOk,
        'searchCount': searchCount,
        'searchMs': searchMs,
        'chaptersOk': chaptersOk,
        'chapterCount': chapterCount,
        'pagesOk': pagesOk,
        'pageSummary': pageSummary,
        'totalMs': totalMs,
        'error': error,
        'steps': steps,
      };

  static SourceTestReport? fromJson(Object? raw) {
    if (raw is! Map || raw['sourceId'] is! String) return null;
    final at = DateTime.tryParse('${raw['at']}');
    if (at == null) return null;
    int? n(String k) => raw[k] is int ? raw[k] as int : null;
    bool? b(String k) => raw[k] is bool ? raw[k] as bool : null;
    return SourceTestReport(
      sourceId: raw['sourceId'] as String,
      at: at,
      status: SourceStatusLabel.parse(raw['status'] as String?),
      searchOk: b('searchOk'),
      searchCount: n('searchCount') ?? 0,
      searchMs: n('searchMs'),
      chaptersOk: b('chaptersOk'),
      chapterCount: n('chapterCount') ?? 0,
      pagesOk: b('pagesOk'),
      pageSummary: raw['pageSummary'] is String ? raw['pageSummary'] as String : null,
      totalMs: n('totalMs'),
      error: raw['error'] is String ? raw['error'] as String : null,
      steps: [for (final s in (raw['steps'] is List ? raw['steps'] as List : const [])) if (s is String) s],
    );
  }
}

/// Rolling reliability statistics of one connector (reads in real use).
class ConnectorStats {
  ConnectorStats(this.sourceId);

  final String sourceId;
  int successes = 0;
  int failures = 0;
  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;
  String? lastError;
  double? avgLatencyMs;
  SourceTestReport? lastTest;

  /// 0..1, optimistic for unknown sources so they still get tried.
  double get reliability {
    final total = successes + failures;
    if (total == 0) return 0.6;
    // Laplace smoothing keeps one failure from burying a source forever.
    return (successes + 1) / (total + 2);
  }

  void recordSuccess(Duration elapsed) {
    successes++;
    lastSuccessAt = DateTime.now();
    final ms = elapsed.inMilliseconds.toDouble();
    avgLatencyMs = avgLatencyMs == null ? ms : avgLatencyMs! * 0.7 + ms * 0.3;
    _decay();
  }

  void recordFailure(String error) {
    failures++;
    lastFailureAt = DateTime.now();
    lastError = error.length > 300 ? '${error.substring(0, 300)}…' : error;
    _decay();
  }

  /// Old history weighs less: halve counters past 50 observations.
  void _decay() {
    if (successes + failures > 50) {
      successes = (successes / 2).ceil();
      failures = (failures / 2).ceil();
    }
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'successes': successes,
        'failures': failures,
        'lastSuccessAt': lastSuccessAt?.toIso8601String(),
        'lastFailureAt': lastFailureAt?.toIso8601String(),
        'lastError': lastError,
        'avgLatencyMs': avgLatencyMs,
        'lastTest': lastTest?.toJson(),
      };

  static ConnectorStats? fromJson(Object? raw) {
    if (raw is! Map || raw['sourceId'] is! String) return null;
    final s = ConnectorStats(raw['sourceId'] as String)
      ..successes = raw['successes'] is int ? raw['successes'] as int : 0
      ..failures = raw['failures'] is int ? raw['failures'] as int : 0
      ..lastSuccessAt = DateTime.tryParse('${raw['lastSuccessAt']}')
      ..lastFailureAt = DateTime.tryParse('${raw['lastFailureAt']}')
      ..lastError = raw['lastError'] is String ? raw['lastError'] as String : null
      ..avgLatencyMs = raw['avgLatencyMs'] is num ? (raw['avgLatencyMs'] as num).toDouble() : null
      ..lastTest = SourceTestReport.fromJson(raw['lastTest']);
    return s;
  }
}

/// Persistence of connector health (JSON, atomic write, .bak kept).
/// SQLite/drift is deliberately not introduced in 2.0 — see docs/MOTEUR_2.0.md.
class ConnectorHealthStore {
  ConnectorHealthStore([this.file]);

  /// Null in tests: statistics stay in memory.
  File? file;
  final Map<String, ConnectorStats> stats = {};

  ConnectorStats of(String sourceId) => stats.putIfAbsent(sourceId, () => ConnectorStats(sourceId));

  Future<void> load() async {
    final file = this.file;
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['format'] != 'pazulu-connector-health' || raw['items'] is! List) {
        return;
      }
      for (final item in raw['items'] as List) {
        final s = ConnectorStats.fromJson(item);
        if (s != null) stats[s.sourceId] = s;
      }
    } catch (_) {
      // A corrupt health file only loses statistics; never block startup.
    }
  }

  Future<void>? _saving;
  bool _again = false;

  /// Saves are serialized and coalesced: many sources finishing at the same
  /// time used to start overlapping writes that collided on Windows
  /// (« Cannot copy file … .bak »).
  Future<void> save() {
    if (_saving != null) {
      _again = true;
      return _saving!;
    }
    final run = _saveLoop();
    _saving = run;
    return run;
  }

  Future<void> _saveLoop() async {
    try {
      do {
        _again = false;
        await _write();
      } while (_again);
    } catch (_) {
      // Statistics only: a failed write never disturbs reading.
    } finally {
      _saving = null;
    }
  }

  Future<void> _write() async {
    final file = this.file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format': 'pazulu-connector-health',
      'schemaVersion': 1,
      'items': stats.values.map((s) => s.toJson()).toList(),
    }), flush: true);
    if (await file.exists()) {
      final bak = File('${file.path}.bak');
      if (await bak.exists()) await bak.delete();
      await file.copy(bak.path);
    }
    // rename() replaces the existing file atomically on Windows and Linux.
    await tmp.rename(file.path);
  }
}
