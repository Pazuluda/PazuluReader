import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Donne accès à [AppState] dans l'arbre de widgets.
///
/// [notifier] peut être un relais ([PausedScope]) : les pages cachées
/// (onglet inactif, écran recouvert) ne se reconstruisent plus à chaque
/// changement, seulement une fois quand elles redeviennent visibles.
class AppScope extends InheritedNotifier<Listenable> {
  AppScope({super.key, required this.state, required super.child, Listenable? notifier})
      : super(notifier: notifier ?? state);

  final AppState state;

  /// Accès avec reconstruction quand l'état change.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.state;

  /// Accès ponctuel, sans abonnement (callbacks, initState…).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.state;
}

/// Part of the screen that is not visible right now (another tab, or the
/// main screen under an opened work): it keeps its state but is not
/// rebuilt at every change of the data. When it becomes visible again, it
/// is rebuilt once if something changed meanwhile.
class PausedScope extends StatefulWidget {
  const PausedScope({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<PausedScope> createState() => _PausedScopeState();
}

class _PausedScopeState extends State<PausedScope> {
  final _relay = _Relay();
  AppState? _state;

  void _onChange() {
    if (widget.active) {
      _relay.fire();
    } else {
      _relay.pending = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.getInheritedWidgetOfExactType<AppScope>()?.state;
    if (!identical(s, _state)) {
      _state?.removeListener(_onChange);
      _state = s?..addListener(_onChange);
    }
  }

  @override
  void didUpdateWidget(covariant PausedScope old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && _relay.pending) {
      _relay.pending = false;
      // After this frame: the page is shown again, up to date.
      WidgetsBinding.instance.addPostFrameCallback((_) => _relay.fire());
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_onChange);
    _relay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    // No app data above (isolated widget): nothing to pause.
    return s == null ? widget.child : AppScope(state: s, notifier: _relay, child: widget.child);
  }
}

class _Relay extends ChangeNotifier {
  bool pending = false;
  void fire() => notifyListeners();
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
