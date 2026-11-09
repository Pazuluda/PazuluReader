import 'dart:async';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/material.dart';

import 'core/app_state.dart';
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
  // First launch, or back after a few hours: releases and library chapter
  // lists are updated now, once, instead of on every fiche.
  await state.warmUp(onStep: progress.report);
  progress.reached(5);
  await progress.finish();
  runApp(PazuluApp(state: state));
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
      onExitRequested: () async {
        await widget.state.flush();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final theme = _themeFor(state.settings.themeId, state.settings.darkMode);
          return MaterialApp(
            title: 'Pazulu Reader',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: state.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            themeAnimationDuration: state.settings.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 450),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(disableAnimations: mq.disableAnimations || state.settings.reduceMotion),
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
