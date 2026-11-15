import 'dart:ffi';
import 'dart:io';

/// La fenêtre de Pazulu sous Windows (réduire / restaurer), sans paquet
/// supplémentaire. Ne touche que la fenêtre de ce processus.
class WinWindow {
  WinWindow._();

  static int? _hwnd;

  static int? _find() {
    if (!Platform.isWindows) return null;
    if (_hwnd != null) return _hwnd;
    try {
      final user = DynamicLibrary.open('user32.dll');
      final kernel = DynamicLibrary.open('kernel32.dll');
      final findWindow = user.lookupFunction<IntPtr Function(Pointer<Uint16>, Pointer<Uint16>),
          int Function(Pointer<Uint16>, Pointer<Uint16>)>('FindWindowW');
      final threadPid = user.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
      final alloc = kernel.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('GlobalAlloc');
      final free = kernel.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');
      const name = 'FLUTTER_RUNNER_WIN32_WINDOW';
      final mem = alloc(0x40, (name.length + 1) * 2 + 8);
      if (mem == 0) return null;
      try {
        final str = Pointer<Uint16>.fromAddress(mem);
        for (var i = 0; i < name.length; i++) {
          str[i] = name.codeUnitAt(i);
        }
        str[name.length] = 0;
        final hwnd = findWindow(str, nullptr);
        if (hwnd == 0) return null;
        final pidPtr = Pointer<Uint32>.fromAddress(mem + (((name.length + 1) * 2 + 3) & ~3));
        threadPid(hwnd, pidPtr);
        if (pidPtr.value != pid) return null; // another app's window: never touched
        return _hwnd = hwnd;
      } finally {
        free(mem);
      }
    } catch (_) {
      return null;
    }
  }

  static void _show(int cmd) {
    final hwnd = _find();
    if (hwnd == null) return;
    try {
      final user = DynamicLibrary.open('user32.dll');
      final show = user.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
      show(hwnd, cmd);
    } catch (_) {}
  }

  /// Réduit la fenêtre dans la barre des tâches.
  static void minimize() => _show(6); // SW_MINIMIZE
}
