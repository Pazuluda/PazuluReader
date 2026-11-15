import 'dart:ffi';
import 'dart:io';

/// What the computer can take: fewer parallel jobs and lighter animations
/// on modest PCs (4 threads or less), and a lower process priority while
/// the window is in the background, so that a game or another program in
/// the foreground keeps the processor.
class DeviceProfile {
  DeviceProfile._();

  static final int processors = Platform.numberOfProcessors;

  /// 4 logical processors or fewer.
  static bool get lowEnd => processors <= 4;

  /// « auto » | « light » | « full » (Settings.performanceMode).
  static String mode = 'auto';

  static bool get light => mode == 'light' || (mode == 'auto' && lowEnd);

  /// Sites whose catalogue is read at the same time.
  static int get crawlWorkers => light ? 3 : 8;

  /// Engines refreshing the library's chapter lists, each taking the next
  /// title as soon as it is free (the requests per site stay limited by
  /// the shared [HostGate]).
  static int get chapterWorkers => light ? 8 : 16;

  /// Engines per language team (French sites / English sites); a team
  /// with nothing left helps the other one.
  static int get enginesPerLanguage => light ? 4 : 8;

  /// Requests at the same time on one site.
  static const int requestsPerSite = 2;

  /// Shortest gap between two refreshes of the screens by background work.
  static Duration get notifyGap =>
      light ? const Duration(milliseconds: 1000) : const Duration(milliseconds: 400);

  static bool? _background;

  /// Windows: BELOW_NORMAL while the window is hidden / unfocused, NORMAL in
  /// front. Only the app's own process; never any other program.
  static void setBackground(bool background) {
    if (!Platform.isWindows || _background == background) return;
    _background = background;
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final current = kernel.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
      final setPriority = kernel.lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
          'SetPriorityClass');
      const normal = 0x00000020, belowNormal = 0x00004000;
      setPriority(current(), background ? belowNormal : normal);
    } catch (_) {
      // Not available: the priority stays as it is.
    }
  }
}
