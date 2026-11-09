import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// Real start-up steps of Pazulu, shown by the 6 segments of the logo's bar.
/// A segment is filled only when its step is really done; the segment of
/// the step in progress blinks (nothing is estimated or invented).
class StartupProgress {
  static const total = 6;

  /// Completed steps (0…6).
  final steps = ValueNotifier<int>(0);
  final label = ValueNotifier<String>('Démarrage…');

  /// Dark background once the profile is read (null: Windows' setting).
  final dark = ValueNotifier<bool?>(null);

  final _exited = Completer<void>();

  /// Steps reported by AppState.init / warmUp.
  static int? completedBefore(String step) {
    final s = step.toLowerCase();
    if (s.startsWith('ouverture du profil')) return 0;
    if (s.startsWith('chargement des sources')) return 1;
    if (s.startsWith('préparation du moteur')) return 2;
    if (s.startsWith('chargement de la bibliothèque')) return 3;
    if (s.startsWith('catalogues') || s.startsWith('chapitres') ||
        s.startsWith('recherche') || s.startsWith('statut')) {
      return 4;
    }
    return null;
  }

  void report(String step) {
    label.value = step;
    final done = completedBefore(step);
    if (done != null) reached(done);
  }

  void reached(int done) {
    if (done > steps.value) steps.value = done.clamp(0, total);
  }

  /// Last segment, then the logo leaves; resolves when the app can appear.
  Future<void> finish() async {
    label.value = 'Prêt';
    reached(total);
    try {
      await _exited.future.timeout(const Duration(milliseconds: 2500));
    } on TimeoutException {
      // never keep the app waiting for an animation
    }
  }

  void _markExited() {
    if (!_exited.isCompleted) _exited.complete();
  }
}

/// Start-up screen: the Pazulu Reader logo (layers of the original image,
/// 944 × 819) built and animated piece by piece; at rest it is exactly
/// the original logo.
class PazuluSplash extends StatelessWidget {
  const PazuluSplash({super.key, required this.progress});

  final StartupProgress progress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: kBodyFont),
      home: _SplashBody(progress: progress),
    );
  }
}

class _SplashBody extends StatefulWidget {
  const _SplashBody({required this.progress});

  final StartupProgress progress;

  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _exit =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _reduced = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.progress.steps.addListener(_onSteps);
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_reduced) _idle.repeat();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Windows « Afficher les animations » off: the logo appears still.
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _intro.value = 1;
      _idle.stop();
    } else if (!_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
    }
  }

  void _onSteps() {
    if (widget.progress.steps.value >= StartupProgress.total) unawaited(_leave());
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    if (_reduced) {
      widget.progress._markExited();
      return;
    }
    // Let the intro end and the last segment fill, then step aside.
    if (_intro.isAnimating) await _intro.forward().orCancel.catchError((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) await _exit.forward().orCancel.catchError((_) {});
    widget.progress._markExited();
  }

  @override
  void dispose() {
    widget.progress.steps.removeListener(_onSteps);
    widget.progress._markExited();
    _intro.dispose();
    _idle.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: widget.progress.dark,
      builder: (context, darkSetting, _) {
        final dark = darkSetting ?? MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final bg = dark ? const Color(0xFF121212) : const Color(0xFFF2F1EC);
        final dots = dark ? const Color(0x1AFFFFFF) : const Color(0x1C111111);
        final ink = dark ? const Color(0xFFF2F1EC) : const Color(0xFF111111);
        return Scaffold(
          backgroundColor: bg,
          body: CustomPaint(
            painter: HalftonePainter(dots),
            child: AnimatedBuilder(
              animation: _exit,
              builder: (context, child) {
                final e = Curves.easeInCubic.transform(_exit.value);
                return Opacity(
                  opacity: 1 - e,
                  child: Transform.scale(scale: 1 + 0.06 * e, child: child),
                );
              },
              child: LayoutBuilder(builder: (context, box) {
                final width = math.min(box.maxWidth * 0.62, 620.0);
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: width,
                      height: width * _Logo.h / _Logo.w,
                      child: FittedBox(
                        child: SizedBox(
                          width: _Logo.w,
                          height: _Logo.h,
                          child: RepaintBoundary(
                            child: _Logo(intro: _intro, idle: _idle, steps: widget.progress.steps,
                                reduced: _reduced),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<String>(
                      valueListenable: widget.progress.label,
                      builder: (_, s, __) => Text(s.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                    ),
                  ]),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// The logo, redrawn in vectors from the original (each piece complete, so
/// nothing is ever uncovered while it moves), in the 944 × 819 space.
/// Pieces are 2× PNGs in assets/logo; at rest they make the whole logo.
class _Logo extends StatelessWidget {
  const _Logo({required this.intro, required this.idle, required this.steps, required this.reduced});

  static const w = 944.0;
  static const h = 819.0;

  /// Position and size of each piece (944 × 819 space).
  static const _box = <String, (double, double, double, double)>{
    'halo': (197, 128, 446, 324),
    'trail': (245, 199, 129, 92),
    'star_big': (377, 147, 106, 108),
    'star_top': (479, 158, 38, 40),
    'star_low': (332, 237, 54, 56),
    'eclat_top': (599, 111, 63, 79),
    'eclat_mid': (622, 156, 85, 58),
    'eclat_low': (631, 225, 61, 34),
    'back_left': (92, 324, 128, 134),
    'sheet3': (393, 337, 336, 122),
    'sheet2': (378, 293, 305, 160),
    'sheet1': (364, 263, 275, 184),
    'page_left': (167, 297, 226, 150),
    'page_right': (351, 209, 257, 235),
    'page_back': (351, 209, 257, 235),
    'signet': (374, 641, 115, 101),
    'bar': (108, 570, 670, 114),
    'seg1': (144, 601, 93, 52),
    'seg2': (215, 601, 96, 52),
    'seg3': (289, 601, 96, 52),
    'seg4': (363, 601, 96, 52),
    'seg5': (437, 601, 96, 52),
    'seg6': (511, 601, 96, 52),
    'banner_black': (8, 423, 903, 178),
    'banner_yellow': (18, 436, 480, 153),
  };

  final Animation<double> intro;
  final Animation<double> idle;
  final ValueListenable<int> steps;
  final bool reduced;

  /// Part [a]…[b] of the intro (0…1), eased.
  static double seg(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  static Widget image(String name) {
    final b = _box[name]!;
    return Image.asset('assets/logo/$name.png', width: b.$3, height: b.$4,
        fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true);
  }

  /// A piece at its place; [transform] around [pivot] (944-space point).
  static Widget piece(String name,
      {double opacity = 1, Matrix4? transform, Offset? pivot, Widget Function(Widget)? wrap}) {
    final b = _box[name]!;
    Widget img = image(name);
    if (wrap != null) img = wrap(img);
    if (transform != null) {
      img = Transform(
        transform: transform,
        origin: pivot == null ? Offset(b.$3 / 2, b.$4 / 2) : pivot - Offset(b.$1, b.$2),
        child: img,
      );
    }
    if (opacity < 1) img = Opacity(opacity: opacity.clamp(0.0, 1.0), child: img);
    return Positioned(left: b.$1, top: b.$2, width: b.$3, height: b.$4, child: img);
  }

  static Matrix4 scaleRot(double s, [double angle = 0]) =>
      Matrix4.rotationZ(angle)..multiply(Matrix4.diagonal3Values(s, s, 1));

  static Matrix4 move(double dx, double dy) => Matrix4.translationValues(dx, dy, 0);

  /// Left-to-right reveal (the dashed trail is « drawn »).
  static Widget Function(Widget) reveal(double f) => (img) => ClipRect(
        child: Align(alignment: Alignment.centerLeft, widthFactor: f.clamp(0.0001, 1.0), child: img),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([intro, idle]),
      builder: (context, _) {
        final t = intro.value;
        final i = reduced ? 0.0 : idle.value;
        final live = t >= 1 && !reduced;
        double wave(double phase, [double speed = 1]) => math.sin(2 * math.pi * (i * speed + phase));

        // Intro timeline (0…1 over 1.5 s).
        final halo = seg(t, 0.00, 0.28, Curves.easeOutBack);
        final book = seg(t, 0.10, 0.38, Curves.easeOutBack);
        final bannerY = seg(t, 0.18, 0.46, Curves.easeOutBack);
        final bannerK = seg(t, 0.24, 0.52, Curves.easeOutBack);
        final bar = seg(t, 0.34, 0.60, Curves.easeOutCubic);
        final signet = seg(t, 0.52, 0.86, Curves.bounceOut);
        final trail = seg(t, 0.40, 0.66, Curves.easeInOutCubic);
        final flipIn = seg(t, 0.28, 0.70, Curves.easeInOutCubic);
        double star(double a) => seg(t, a, a + 0.26, Curves.elasticOut);
        double burst(double a) => seg(t, a, a + 0.16, Curves.easeOutBack);

        // The right page opens during the intro (rises from its edge and
        // lies down), then flutters now and then: it never goes over to
        // the left, so its shape always matches the book.
        double bump(double a, double b) {
          final u = ((i - a) / (b - a)).clamp(0.0, 1.0);
          final v = math.sin(math.pi * u);
          return v * v;
        }
        var angle = math.pi / 2 * (1 - flipIn);
        if (live) angle = math.max(0.34 * math.pi * bump(0.12, 0.46), 0.17 * math.pi * bump(0.56, 0.76));
        final showSheet = (flipIn > 0 && flipIn < 1) || (live && angle > 0.002);

        // Idle life (3.6 s loop): the book floats, the halo breathes, the
        // stars sparkle and turn, the bursts flare, the trail is drawn again,
        // the bookmark swings, the full segments ripple.
        final bob = live ? math.sin(2 * math.pi * i) : 0.0;
        double twinkle(double phase) => live ? 1 + 0.14 * wave(phase) : 1;
        double sparkle(double phase) {
          if (!live) return 1;
          final v = math.max(0.0, wave(phase));
          return 1 + 0.35 * v * v * v * v;
        }
        // Short « pop » once per loop, around [at].
        double pop(double at) {
          final u = ((i - at) / 0.14).clamp(0.0, 1.0);
          return math.sin(math.pi * u);
        }
        double flare(double phase) => live ? 1 + 0.24 * (0.5 + 0.5 * wave(phase, 2)) : 1;
        final trailNow = live ? ((i - 0.04) / 0.34).clamp(0.0, 1.0) : trail;
        final trailOpacity = live && i > 0.88 ? 1 - (i - 0.88) / 0.12 : 1.0;

        Widget sheetPiece() => piece('page_right',
            pivot: const Offset(358, 437),
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            wrap: (img) => ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.25 * math.sin(angle).abs()), BlendMode.srcATop),
                  child: img,
                ));

        return Stack(clipBehavior: Clip.none, children: [
          piece('halo', opacity: halo * 1.5,
              transform: scaleRot((0.35 + 0.65 * halo) * (live ? 1 + 0.018 * wave(0.25) : 1)),
              pivot: const Offset(420, 450)),
          if (trailNow > 0) piece('trail', opacity: trailOpacity, wrap: reveal(trailNow)),
          piece('star_big',
              transform: scaleRot(star(0.46) * twinkle(0), (1 - star(0.46)) * 1.4 + (live ? 0.18 * wave(0.2) : 0)),
              pivot: const Offset(430, 201)),
          piece('star_top', transform: scaleRot(star(0.56) * sparkle(0.33), live ? 2 * math.pi * i : 0),
              pivot: const Offset(498, 178)),
          piece('star_low', transform: scaleRot(star(0.51) * sparkle(0.66), live ? -0.25 * wave(0.1) : 0),
              pivot: const Offset(359, 265)),
          piece('eclat_top', transform: scaleRot(burst(0.66) * flare(0)), pivot: const Offset(606, 183)),
          piece('eclat_mid', transform: scaleRot(burst(0.70) * flare(0.3)), pivot: const Offset(629, 207)),
          piece('eclat_low', transform: scaleRot(burst(0.74) * flare(0.6)), pivot: const Offset(638, 232)),
          // The book rises as one piece, then floats; the turning page moves
          // with it.
          Positioned.fill(
            child: Opacity(
              opacity: (book * 1.4).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 40 * (1 - book) - 5 * bob),
                child: Stack(clipBehavior: Clip.none, children: [
                  piece('back_left'),
                  piece('sheet3'),
                  piece('sheet2'),
                  piece('sheet1'),
                  piece('page_left'),
                  // During the intro the page opens by itself (no still copy).
                  if (flipIn >= 1) piece('page_right'),
                  if (showSheet) sheetPiece(),
                ]),
              ),
            ),
          ),
          // The bookmark (« la cravate ») swings and flaps like a ribbon.
          piece('signet', opacity: signet > 0 ? 1 : 0,
              transform: Matrix4.translationValues(0, -70 * (1 - signet), 0)
                ..multiply(Matrix4.rotationZ(live ? 0.13 * wave(0.15) : 0))
                ..multiply(Matrix4.skewX(live ? 0.16 * wave(0.4, 2) : 0))
                ..multiply(Matrix4.diagonal3Values(1, live ? 1 + 0.06 * wave(0.1, 2) : 1, 1)),
              pivot: const Offset(436, 650)),
          piece('bar', opacity: bar, transform: Matrix4.diagonal3Values(0.2 + 0.8 * bar, 1, 1),
              pivot: const Offset(443, 627)),
          ..._segments(t, i, bar),
          // PAZULU and READER rock gently, out of step, with a little pop.
          piece('banner_black', opacity: bannerK * 1.5,
              transform: move(140 * (1 - bannerK), live ? -5 * wave(0.5) : 0)
                ..multiply(Matrix4.rotationZ(live ? -0.022 * wave(0.5) : 0))
                ..multiply(Matrix4.diagonal3Values(
                    live ? 1 + 0.025 * pop(0.30) : 1, live ? 1 + 0.025 * pop(0.30) : 1, 1)),
              pivot: const Offset(690, 500)),
          piece('banner_yellow', opacity: bannerY * 1.5,
              transform: move(-140 * (1 - bannerY), live ? -5 * wave(0.75) : 0)
                ..multiply(Matrix4.rotationZ(live ? 0.028 * wave(0.75) : 0))
                ..multiply(Matrix4.diagonal3Values(
                    live ? 1 + 0.035 * pop(0.18) : 1, live ? 1 + 0.035 * pop(0.18) : 1, 1)),
              pivot: const Offset(258, 512)),
        ]);
      },
    );
  }

  /// A small wave runs along the full segments, once per loop.
  double _ripple(double t, double i, int k) {
    if (t < 1 || reduced) return 0;
    final v = math.max(0.0, math.sin(2 * math.pi * (i - 0.08 * k)));
    return 0.09 * math.pow(v, 10).toDouble();
  }

  List<Widget> _segments(double t, double i, double bar) {
    return [
      for (var k = 0; k < 6; k++)
        Builder(builder: (context) {
          final b = _box['seg${k + 1}']!;
          return Positioned(
            left: b.$1,
            top: b.$2,
            width: b.$3,
            height: b.$4,
            child: ValueListenableBuilder<int>(
              valueListenable: steps,
              builder: (_, done, __) {
                final filled = k < done;
                // The step in progress blinks gently once the bar is there.
                final active = k == done && bar >= 1;
                return TweenAnimationBuilder<double>(
                  tween: Tween(end: filled ? 1 : 0),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  builder: (_, f, child) {
                    final pulse = active && !reduced ? 0.15 + 0.25 * (0.5 + 0.5 * math.sin(2 * math.pi * i * 3)) : 0.0;
                    final o = math.max(f.clamp(0.0, 1.0), pulse);
                    if (o <= 0) return const SizedBox.shrink();
                    return Opacity(
                      opacity: o.toDouble(),
                      child: Transform.scale(
                          scale: filled ? (0.6 + 0.4 * f) * (1 + _ripple(t, i, k)) : 1, child: child),
                    );
                  },
                  child: image('seg${k + 1}'),
                );
              },
            ),
          );
        }),
    ];
  }
}
