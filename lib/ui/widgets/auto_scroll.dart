import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Défilement automatique au clic molette, comme dans un navigateur :
/// un clic molette pose un point d'ancrage ; plus la souris s'en éloigne
/// vers le bas (ou le haut), plus la page défile vite dans ce sens. Un
/// nouveau clic (n'importe quel bouton), la molette ou Échap l'arrête.
/// Maintenir la molette enfoncée en bougeant puis la relâcher l'arrête
/// aussi.
class AutoScrollArea extends StatefulWidget {
  const AutoScrollArea({super.key, required this.controller, required this.child, this.enabled = true});

  final ScrollController controller;
  final Widget child;
  final bool enabled;

  @override
  State<AutoScrollArea> createState() => AutoScrollAreaState();
}

class AutoScrollAreaState extends State<AutoScrollArea> with SingleTickerProviderStateMixin {
  /// Distance (px) autour du point d'ancrage où rien ne bouge.
  static const double deadZone = 14;

  /// Vitesse (px par seconde) pour une distance [distance] au point
  /// d'ancrage : lente près du point, rapide loin, plafonnée.
  static double speedFor(double distance) {
    final d = distance.abs() - deadZone;
    if (d <= 0) return 0;
    final v = d * 7 + d * d * 0.05;
    return (v > 6000 ? 6000 : v) * distance.sign;
  }

  late final Ticker _ticker = createTicker(_tick);
  Offset? _anchor;
  Offset _pointer = Offset.zero;
  Duration _last = Duration.zero;
  DateTime _pressedAt = DateTime(2000);
  bool _movedWhilePressed = false;

  bool get active => _anchor != null;

  DateTime _stoppedAt = DateTime(2000);

  /// Le clic qui vient d'arrêter le défilement ne doit rien faire d'autre
  /// (ne pas afficher / masquer les barres du lecteur).
  bool get justStopped => DateTime.now().difference(_stoppedAt) < const Duration(milliseconds: 400);

  void stop() {
    if (_anchor == null) return;
    _ticker.stop();
    setState(() => _anchor = null);
  }

  void _start(Offset at) {
    _anchor = at;
    _pointer = at;
    _last = Duration.zero;
    _pressedAt = DateTime.now();
    _movedWhilePressed = false;
    _ticker.start();
    setState(() {});
  }

  void _tick(Duration elapsed) {
    final anchor = _anchor;
    final c = widget.controller;
    if (anchor == null || !c.hasClients) return;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.1) return; // première image ou fenêtre figée
    final v = speedFor(_pointer.dy - anchor.dy);
    if (v == 0) return;
    final pos = c.position;
    final next = (pos.pixels + v * dt).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next != pos.pixels) c.jumpTo(next);
  }

  @override
  void didUpdateWidget(covariant AutoScrollArea old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && active) stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor;
    final dy = anchor == null ? 0.0 : _pointer.dy - anchor.dy;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (!widget.enabled || e.kind != PointerDeviceKind.mouse) return;
        if (active) {
          _stoppedAt = DateTime.now();
          stop(); // n'importe quel clic arrête
        } else if (e.buttons & kMiddleMouseButton != 0) {
          _start(e.localPosition);
        }
      },
      onPointerMove: (e) {
        if (!active) return;
        _pointer = e.localPosition;
        if ((e.localPosition - _anchor!).distance > deadZone) _movedWhilePressed = true;
        setState(() {});
      },
      onPointerHover: (e) {
        if (!active) return;
        _pointer = e.localPosition;
        setState(() {});
      },
      onPointerUp: (e) {
        // Molette maintenue en bougeant, puis relâchée : arrêt (comme un
        // navigateur). Un simple clic laisse le défilement actif.
        if (active && _movedWhilePressed &&
            DateTime.now().difference(_pressedAt) > const Duration(milliseconds: 350)) {
          stop();
        }
      },
      onPointerSignal: (e) {
        if (active && e is PointerScrollEvent) stop();
      },
      child: MouseRegion(
        cursor: anchor == null
            ? MouseCursor.defer
            : (dy.abs() <= deadZone ? SystemMouseCursors.allScroll : SystemMouseCursors.resizeUpDown),
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (anchor != null)
              Positioned(
                left: anchor.dx - 16,
                top: anchor.dy - 16,
                child: IgnorePointer(child: _AnchorMark(direction: speedFor(dy).sign)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le point d'ancrage : un rond avec deux flèches, celle du sens actif
/// mise en avant.
class _AnchorMark extends StatelessWidget {
  const _AnchorMark({required this.direction});

  final double direction;

  @override
  Widget build(BuildContext context) {
    Color tone(bool on) => on ? Colors.black : Colors.black38;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: tone(direction < 0)),
          Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle)),
          Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: tone(direction > 0)),
        ],
      ),
    );
  }
}
