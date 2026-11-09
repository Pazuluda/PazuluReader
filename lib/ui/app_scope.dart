import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Donne accès à [AppState] dans l'arbre de widgets.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Accès avec reconstruction quand l'état change.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Accès ponctuel, sans abonnement (callbacks, initState…).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Ouvre une page avec une transition courte, ou instantanée si
/// l'utilisateur a demandé moins d'animations.
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 260),
      reverseTransitionDuration:
          reduce ? Duration.zero : const Duration(milliseconds: 170),
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}
