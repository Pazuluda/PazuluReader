import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

/// Journal simple : console + fichier `pazulu.log` (remis à zéro au-delà de 1 Mo).
///
/// Les lignes sont regroupées et écrites une fois par seconde, sans bloquer
/// l'interface (avant : une écriture disque à chaque ligne).
class AppLog {
  static File? _file;
  static final StringBuffer _pending = StringBuffer();
  static Timer? _flushTimer;
  static Future<void>? _writing;

  static void init(Directory dir) {
    _file = File('${dir.path}${Platform.pathSeparator}pazulu.log');
    try {
      final f = _file!;
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        f.writeAsStringSync('');
      }
    } catch (_) {
      // Le journal ne doit jamais empêcher l'app de démarrer.
    }
  }

  static String? get path => _file?.path;

  static void info(String message) => _write('INFO', message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' : $error');
    if (stack != null) buffer.write('\n$stack');
    _write('ERREUR', buffer.toString());
  }

  static void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    developer.log(line, name: 'pazulu');
    if (_file == null) return;
    _pending.writeln(line);
    _flushTimer ??= Timer(const Duration(seconds: 1), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// Écrit ce qui attend (appelé aussi avant un rapport de bug / à la
  /// fermeture).
  static Future<void> flush() async {
    while (_writing != null) {
      await _writing;
    }
    final f = _file;
    if (f == null || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    final job = () async {
      try {
        await f.writeAsString(text, mode: FileMode.append, flush: false);
      } catch (_) {}
    }();
    _writing = job;
    await job;
    _writing = null;
  }
}
