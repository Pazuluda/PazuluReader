import 'dart:collection';
import 'dart:convert';

enum EngineLogLevel { debug, info, warning, error }

class EngineLogEntry {
  const EngineLogEntry({
    required this.at,
    required this.level,
    required this.event,
    this.sourceId,
    this.message,
    this.elapsedMs,
    this.data = const {},
  });

  final DateTime at;
  final EngineLogLevel level;
  final String event;
  final String? sourceId;
  final String? message;
  final int? elapsedMs;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'level': level.name,
        'event': event,
        if (sourceId != null) 'source': sourceId,
        if (message != null) 'message': message,
        if (elapsedMs != null) 'ms': elapsedMs,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Structured, bounded engine journal. Everything is redacted on entry:
/// cookies, authorization headers, tokens and signed URL parameters never
/// reach memory, disk or an export.
class EngineLog {
  EngineLog({this.capacity = 600});

  final int capacity;
  final ListQueue<EngineLogEntry> _entries = ListQueue();
  void Function(EngineLogEntry entry)? onEntry;

  List<EngineLogEntry> get entries => List.unmodifiable(_entries);

  void add(EngineLogLevel level, String event, {
    String? sourceId,
    String? message,
    Duration? elapsed,
    Map<String, Object?> data = const {},
  }) {
    final entry = EngineLogEntry(
      at: DateTime.now(),
      level: level,
      event: event,
      sourceId: sourceId,
      message: message == null ? null : redact(message),
      elapsedMs: elapsed?.inMilliseconds,
      data: {for (final e in data.entries) e.key: _redactValue(e.key, e.value)},
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    onEntry?.call(entry);
  }

  void info(String event, {String? sourceId, String? message, Duration? elapsed,
      Map<String, Object?> data = const {}}) =>
      add(EngineLogLevel.info, event, sourceId: sourceId, message: message,
          elapsed: elapsed, data: data);

  void warn(String event, {String? sourceId, String? message, Duration? elapsed,
      Map<String, Object?> data = const {}}) =>
      add(EngineLogLevel.warning, event, sourceId: sourceId, message: message,
          elapsed: elapsed, data: data);

  void error(String event, {String? sourceId, String? message, Duration? elapsed,
      Map<String, Object?> data = const {}}) =>
      add(EngineLogLevel.error, event, sourceId: sourceId, message: message,
          elapsed: elapsed, data: data);

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'format': 'pazulu-engine-log',
        'schemaVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'entries': _entries.map((e) => e.toJson()).toList(),
      });

  void clear() => _entries.clear();

  static const _sensitiveKeys = {
    'cookie', 'set-cookie', 'authorization', 'token', 'access_token',
    'refresh_token', 'session', 'password', 'secret', 'apikey', 'api_key',
  };

  static Object? _redactValue(String key, Object? value) {
    if (_sensitiveKeys.contains(key.toLowerCase())) return '[masqué]';
    if (value is String) return redact(value);
    if (value is num || value is bool || value == null) return value;
    return redact('$value');
  }

  /// Removes secrets from free text and URLs.
  static String redact(String input) {
    var out = input;
    // Signed / tokenised query parameters.
    out = out.replaceAllMapped(
        RegExp(r'([?&](?:token|access_token|auth|key|sig|signature|expires|'
            r'policy|session|sid|hash|hmac|x-amz-[a-z-]+)=)[^&#\s]+',
            caseSensitive: false),
        (m) => '${m.group(1)}[masqué]');
    out = out.replaceAllMapped(
        RegExp(r'((?:cookie|set-cookie|authorization)\s*[:=]\s*)[^\n;]+',
            caseSensitive: false),
        (m) => '${m.group(1)}[masqué]');
    out = out.replaceAllMapped(RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+'),
        (m) => '${m.group(1)}[masqué]');
    // Local user paths (C:\Users\name\…) are personal information.
    out = out.replaceAllMapped(RegExp(r'([A-Za-z]:\\Users\\)[^\\\s]+', caseSensitive: false),
        (m) => '${m.group(1)}[utilisateur]');
    if (out.length > 600) out = '${out.substring(0, 600)}…';
    return out;
  }
}
