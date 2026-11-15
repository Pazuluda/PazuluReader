import 'dart:async';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/device_profile.dart';
import 'core/log.dart';
import 'design/theme.dart';
import 'ui/app_scope.dart';
import 'ui/shell.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppLog.error('Erreur Flutter', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  // A widget that fails must never leave a black or grey screen: a readable
  // message is shown in its place, the rest of the app keeps working
  // (back button, navigation) and the error goes to the log.
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFF14141F),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24)),
              const SizedBox(height: 8),
              const Text('Cet élément n\'a pas pu s\'afficher.',
                  style: TextStyle(color: Color(0xFFECEDF5), fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${details.exception}', maxLines: 3, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFA3A6BF), fontSize: 12)),
            ],
          ),
        ),
      );
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('Erreur non gérée', error, stack);
    return true;
  };

  // Splash (logo + current step) while the profile, the 200+ sources and
  // the library load; replaced by the app as soon as everything is ready.
  // The animated logo's bar follows the real steps (6 segments).
  final progress = StartupProgress();
  runApp(PazuluSplash(progress: progress));
  final state = AppState();
  await state.init(onStep: progress.report);
  progress
    ..reached(4)
    ..dark.value = state.settings.darkMode;
  // The app opens as soon as the profile and the library are read. The
  // updates (site catalogues, chapter lists, new chapters, statuses) run
  // afterwards in background, shown discreetly in the header: the library
  // is usable at once, even on a modest PC.
  // Modest PC (light mode): the update is done here, on the splash, in one
  // go and limited in time; once the app is open, background work steps
  // aside as soon as the user does something. Other PCs: the app opens at
  // once and updates in background.
  if (DeviceProfile.light) {
    await state.warmUp(onStep: progress.report, onSplash: true);
  }
  progress.reached(5);
  await progress.finish();
  // Every click, scroll or key press: light mode pauses background work.
  GestureBinding.instance.pointerRouter.addGlobalRoute((_) => state.touch());
  HardwareKeyboard.instance.addHandler((_) {
    state.touch();
    return false;
  });
  runApp(PazuluApp(state: state));
  if (!DeviceProfile.light) {
    Timer(const Duration(seconds: 2), () {
      unawaited(state.warmUp(onStep: (step) => state.backgroundStep.value = step)
          .whenComplete(() => state.backgroundStep.value = null));
    });
  }
}

class PazuluApp extends StatefulWidget {
  const PazuluApp({super.key, required this.state});

  final AppState state;

  @override
  State<PazuluApp> createState() => _PazuluAppState();
}

class _PazuluAppState extends State<PazuluApp> {
  late final AppLifecycleListener _lifecycle;
  String? _themeKey;
  ThemeData? _theme;

  @override
  void initState() {
    super.initState();
    _appearance.value = _lookOf(widget.state);
    widget.state.addListener(_onState);
    // Enregistre la bibliothèque dès que l'app passe en arrière-plan ou se ferme.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        widget.state.setActive(false);
        unawaited(widget.state.flush());
      },
      onHide: () {
        widget.state.setActive(false);
        unawaited(widget.state.flush());
      },
      onResume: () => widget.state.setActive(true),
      // Another window in front (a game…): lower priority, work goes on.
      onInactive: () => DeviceProfile.setBackground(true),
      onExitRequested: () async {
        await widget.state.flush();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.state.removeListener(_onState);
    _appearance.dispose();
    super.dispose();
  }

  final _appearance = ValueNotifier<String>('');

  String _lookOf(AppState s) =>
      '${s.settings.themeId}|${s.settings.darkMode}|${s.settings.reduceMotion}|${DeviceProfile.light}';

  void _onState() => _appearance.value = _lookOf(widget.state);

  /// Le thème n'est reconstruit que lorsque la palette change.
  ThemeData _themeFor(String id, bool dark) {
    final key = '$id|$dark';
    if (_theme == null || _themeKey != key) {
      _themeKey = key;
      _theme = buildPazuluTheme(paletteFor(id, dark: dark));
    }
    return _theme!;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AppScope(
      state: state,
      // Rebuilt only when the look changes (theme, dark mode, animations),
      // not at every change of the library.
      child: ListenableBuilder(
        listenable: _appearance,
        builder: (context, _) {
          final theme = _themeFor(state.settings.themeId, state.settings.darkMode);
          return MaterialApp(
            title: 'Pazulu Reader',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: state.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            themeAnimationDuration: state.settings.reduceMotion || DeviceProfile.light
                ? Duration.zero
                : const Duration(milliseconds: 450),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(disableAnimations:
                    mq.disableAnimations || state.settings.reduceMotion || DeviceProfile.light),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const Shell(),
          );
        },
      ),
    );
  }
}
