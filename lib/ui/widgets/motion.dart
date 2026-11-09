import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// Apparition en cascade : chaque élément arrive un peu après le précédent
/// (fondu + léger glissement vers le haut). Désactivé si l'utilisateur
/// réduit les animations.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.index, required this.child, this.offset = 18});

  final int index;
  final Widget child;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (PazuluMotion.reduced(context)) return child;
    final step = math.min(index, 14);
    final totalMs = 340 + step * 45;
    final start = (step * 45) / totalMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, offset * (1 - v)), child: child),
      ),
    );
  }
}

/// Soulève légèrement l'élément au survol de la souris, avec une lueur
/// de la couleur du thème.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.radius = PazuluRadius.card, this.scale = 1.035});

  final Widget child;
  final double radius;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = PazuluMotion.of(context, PazuluMotion.hover);
    // Kiosque : l'élément se décale en haut à gauche et révèle une ombre
    // d'encre pleine (pas de lueur).
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: d,
        curve: PazuluMotion.curve,
        transform: Matrix4.translationValues(_hover ? -3 : 0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: _hover ? p.ink : p.ink.withValues(alpha: 0), offset: const Offset(6, 6)),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Fond d'ambiance : deux halos lumineux qui dérivent lentement.
class AmbientGlow extends StatefulWidget {
  const AmbientGlow({super.key});

  @override
  State<AmbientGlow> createState() => _AmbientGlowState();
}

class _AmbientGlowState extends State<AmbientGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 22));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PazuluMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final h = box.maxHeight;
                return Stack(
                  children: [
                    _blob(
                      left: w * (0.18 + 0.12 * t),
                      top: -h * (0.45 - 0.08 * math.sin(t * math.pi)),
                      size: math.max(w, h) * 0.6,
                      color: p.accent.withValues(alpha: 0.30),
                    ),
                    _blob(
                      left: w * (0.62 - 0.10 * t),
                      top: h * (0.55 + 0.06 * t),
                      size: math.max(w, h) * 0.55,
                      color: p.primary.withValues(alpha: 0.26),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _blob({required double left, required double top, required double size, required Color color}) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Bloc qui pulse doucement : emplacement réservé pendant un chargement.
class Pulse extends StatefulWidget {
  const Pulse({super.key, this.radius = PazuluRadius.card, this.width, this.height});

  final double radius;
  final double? width;
  final double? height;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PazuluMotion.reduced(context)) {
      _c.value = 0.5;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(p.surface, p.surfaceHigh, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
