import 'dart:developer' as developer;
import 'dart:io';

/// Journal simple : console + fichier `pazulu.log` (remis à zéro au-delà de 1 Mo).
class AppLog {
  static File? _file;

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
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }
}
