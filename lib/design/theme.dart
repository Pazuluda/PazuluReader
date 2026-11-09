import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// Direction artistique « Kiosque » (2.4) : imprimé manga pop. Papier et
/// encre, bordures épaisses, ombres décalées pleines, une couleur d'accent
/// vive au choix. Un vrai mode clair (papier) et un vrai mode sombre (encre).
///
/// Une palette = un accent × un mode. Les champs historiques (primary,
/// bright, surface…) restent pour tous les écrans existants.
class PazuluPalette {
  const PazuluPalette({
    required this.id,
    required this.name,
    required this.dark,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.primary,
    required this.bright,
    required this.accent,
    required this.ink,
    required this.onAccent,
    required this.text,
    required this.muted,
  });

  /// Identifiant de l'accent (« jaune », « rouge »…).
  final String id;
  final String name;

  /// Mode sombre (encre) ou clair (papier).
  final bool dark;

  /// Fond de l'application (papier ou encre).
  final Color background;

  /// Cartes, panneaux.
  final Color surface;

  /// Survol, menus, zones « douces ».
  final Color surfaceHigh;

  /// Fond des boutons pleins = l'accent (texte [onAccent]).
  final Color primary;

  /// Accent lisible comme texte / icône sur le fond (≥ 4.5:1).
  final Color bright;

  /// L'accent brut (pastilles, barres, autocollants).
  final Color accent;

  /// Couleur des traits épais et des ombres décalées.
  final Color ink;

  /// Texte posé sur l'accent.
  final Color onAccent;
  final Color text;
  final Color muted;

  Color get border => ink.withValues(alpha: dark ? 0.16 : 0.14);
  Color get borderStrong => ink;

  Color get card => surface;

  /// Fond d'un élément sélectionné.
  Color get selected => Color.lerp(surface, accent, dark ? 0.22 : 0.35)!;

  Color get success => dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  Color get warning => dark ? const Color(0xFFFBBF24) : const Color(0xFFA16207);
  Color get danger => dark ? const Color(0xFFF87171) : const Color(0xFFC81E1E);

  /// Gardés pour compatibilité : à plat, pas de dégradé dans Kiosque.
  LinearGradient get buttonGradient => LinearGradient(colors: [accent, accent]);

  LinearGradient get heroGradient => LinearGradient(
        colors: [Color.lerp(accent, background, 0.55)!, background],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Trame de points (fond « papier imprimé »).
  Color get halftone => ink.withValues(alpha: dark ? 0.07 : 0.11);
}

/// Les accents proposés (vifs, texte noir dessus ≥ 7:1).
const pazuluAccents = <(String, String, Color)>[
  ('jaune', 'Jaune', Color(0xFFFFD400)),
  ('rouge', 'Rouge', Color(0xFFFF4A3D)),
  ('cyan', 'Cyan', Color(0xFF2CC8E8)),
  ('vert', 'Vert', Color(0xFF3DDC84)),
  ('rose', 'Rose', Color(0xFFFF6FB0)),
  ('orange', 'Orange', Color(0xFFFF9A1F)),
];

PazuluPalette paletteFor(String? id, {bool dark = false}) {
  final a = pazuluAccents.firstWhere((x) => x.$1 == id, orElse: () => pazuluAccents.first);
  final accent = a.$3;
  if (dark) {
    return PazuluPalette(
      id: a.$1, name: a.$2, dark: true,
      background: const Color(0xFF121212),
      surface: const Color(0xFF1C1C1C),
      surfaceHigh: const Color(0xFF2A2A2A),
      primary: accent,
      bright: accent,
      accent: accent,
      ink: const Color(0xFFF3F1EA),
      onAccent: const Color(0xFF111111),
      text: const Color(0xFFF3F1EA),
      muted: const Color(0xFFB5B3AC),
    );
  }
  return PazuluPalette(
    id: a.$1, name: a.$2, dark: false,
    background: const Color(0xFFF2F1EC),
    surface: const Color(0xFFFFFFFF),
    surfaceHigh: const Color(0xFFE4E2DA),
    primary: accent,
    // Un accent vif n'est pas lisible en texte sur papier : version foncée.
    bright: Color.lerp(accent, const Color(0xFF000000), 0.58)!,
    accent: accent,
    ink: const Color(0xFF111111),
    onAccent: const Color(0xFF111111),
    text: const Color(0xFF111111),
    muted: const Color(0xFF4D4D4D),
  );
}

/// Compatibilité : anciennes palettes (« indigo »…) → jaune.
PazuluPalette paletteById(String? id, {bool dark = false}) => paletteFor(id, dark: dark);

List<PazuluPalette> get pazuluPalettes => [for (final a in pazuluAccents) paletteFor(a.$1)];

/// Polices embarquées (aucun téléchargement) : Archivo Black pour les
/// titres, Archivo pour le texte.
const kDisplayFont = 'ArchivoBlack';
const kBodyFont = 'Archivo';

/// Titre « Kiosque » : Archivo Black, majuscules.
TextStyle kiosqueDisplay(double size, {Color? color}) => TextStyle(
      fontFamily: kDisplayFont,
      fontSize: size,
      height: 1.0,
      letterSpacing: -size * 0.025,
      color: color,
    );

/// Bordure épaisse + ombre décalée pleine (« box » de la maquette).
BoxDecoration kiosqueBox(PazuluPalette p, {Color? color, double shadow = 5, double width = 2.5}) =>
    BoxDecoration(
      color: color ?? p.surface,
      border: Border.all(color: p.ink, width: width),
      boxShadow: shadow <= 0 ? null : [BoxShadow(color: p.ink, offset: Offset(shadow, shadow))],
    );

/// Trame de points du fond.
class HalftonePainter extends CustomPainter {
  HalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // One draw call for every dot (round points of 2.4 px), instead of one
    // circle per dot: the background is repainted at once on resize.
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    const step = 9.0;
    final cols = ((size.width - 4.5) / step).ceil().clamp(0, 100000);
    final rows = ((size.height - 4.5) / step).ceil().clamp(0, 100000);
    if (cols == 0 || rows == 0) return;
    final pts = Float32List(cols * rows * 2);
    var i = 0;
    for (var r = 0; r < rows; r++) {
      final y = 4.5 + r * step;
      for (var c = 0; c < cols; c++) {
        pts[i++] = 4.5 + c * step;
        pts[i++] = y;
      }
    }
    canvas.drawRawPoints(PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(HalftonePainter old) => old.color != color;
}

/// Accès à la palette active : `context.pal`.
class PaletteExtension extends ThemeExtension<PaletteExtension> {
  const PaletteExtension(this.palette);

  final PazuluPalette palette;

  @override
  PaletteExtension copyWith({PazuluPalette? palette}) =>
      PaletteExtension(palette ?? this.palette);

  @override
  PaletteExtension lerp(ThemeExtension<PaletteExtension>? other, double t) =>
      t < 0.5 ? this : (other as PaletteExtension? ?? this);
}

extension PaletteContext on BuildContext {
  PazuluPalette get pal =>
      Theme.of(this).extension<PaletteExtension>()?.palette ?? paletteFor(null);
}

/// Espacements (grille 4/8), rayons et durées partagés.
class PazuluSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class PazuluRadius {
  // Kiosque : angles vifs (imprimé), seules les pastilles restent rondes.
  static const sm = 0.0;
  static const card = 0.0;
  static const big = 0.0;
  static const chip = 0.0;
}

class PazuluMotion {
  static const tap = Duration(milliseconds: 120);
  static const enter = Duration(milliseconds: 320);
  static const exit = Duration(milliseconds: 200);
  static const hover = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) => MediaQuery.of(context).disableAnimations;

  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

ThemeData buildPazuluTheme(PazuluPalette p) {
  final scheme = ColorScheme(
    brightness: p.dark ? Brightness.dark : Brightness.light,
    primary: p.primary,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    tertiary: p.bright,
    onTertiary: p.background,
    error: p.danger,
    onError: p.dark ? const Color(0xFF111111) : Colors.white,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    outline: p.ink,
    outlineVariant: p.border,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.background,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceHigh,
    surfaceContainerHighest: p.surfaceHigh,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: p.background,
    splashFactory: InkRipple.splashFactory,
    extensions: [PaletteExtension(p)],
  );

  final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: kBodyFont);
  TextStyle? display(TextStyle? t, double size) => t?.copyWith(
      fontFamily: kDisplayFont, fontWeight: FontWeight.w400, fontSize: size, letterSpacing: -size * 0.02, height: 1.05);
  final ink = BorderSide(color: p.ink, width: 2.5);
  const square = RoundedRectangleBorder();
  final squareInk = RoundedRectangleBorder(side: ink);

  return base.copyWith(
    textTheme: text.copyWith(
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, height: 1.45, color: p.muted),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.3),
      labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: p.muted),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: display(text.titleLarge, 21),
      headlineSmall: display(text.headlineSmall, 28),
      headlineMedium: display(text.headlineMedium, 36),
      headlineLarge: display(text.headlineLarge, 46),
      displaySmall: display(text.displaySmall, 52),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? p.surfaceHigh : p.primary),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? p.muted : p.onAccent),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: 0.4)),
        shape: WidgetStatePropertyAll(squareInk),
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: WidgetStatePropertyAll(p.ink.withValues(alpha: 0.08)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.surface,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: ink,
        textStyle: const TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: 0.3),
        shape: square,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.bright,
        minimumSize: const Size(44, 40),
        textStyle: const TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w800, fontSize: 13.5),
        shape: square,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: p.text,
        hoverColor: p.ink.withValues(alpha: 0.08),
        shape: square,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.ink : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.background : p.text),
        side: WidgetStatePropertyAll(ink),
        shape: const WidgetStatePropertyAll(square),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w800, fontSize: 12.5)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: squareInk,
      titleTextStyle: kiosqueDisplay(22, color: p.text),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: Radius.zero,
      thumbColor: WidgetStatePropertyAll(p.ink.withValues(alpha: 0.35)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      subtitleTextStyle: TextStyle(fontFamily: kBodyFont, color: p.muted, fontSize: 13),
      shape: square,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: p.text,
      titleTextStyle: kiosqueDisplay(20, color: p.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.ink,
      side: BorderSide(color: p.ink, width: 2),
      shape: square,
      labelStyle: TextStyle(fontFamily: kBodyFont, color: p.text, fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(fontFamily: kBodyFont, color: p.background, fontWeight: FontWeight.w800),
      checkmarkColor: p.background,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: ink),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: ink),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.ink, width: 3)),
      hintStyle: TextStyle(color: p.muted),
      prefixIconColor: p.text,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.text,
      selectionColor: p.accent.withValues(alpha: 0.45),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.accent,
      contentTextStyle: TextStyle(fontFamily: kBodyFont, color: p.onAccent, fontWeight: FontWeight.w800),
      actionTextColor: p.onAccent,
      shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF111111), width: 2.5)),
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: squareInk,
      elevation: 0,
      textStyle: TextStyle(fontFamily: kBodyFont, color: p.text, fontWeight: FontWeight.w700),
    ),
    menuTheme: MenuThemeData(style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(p.surface),
      shape: WidgetStatePropertyAll(squareInk),
    )),
    dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.ink,
      thumbColor: p.accent,
      inactiveTrackColor: p.ink.withValues(alpha: 0.18),
      overlayColor: p.accent.withValues(alpha: 0.2),
      trackHeight: 5,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceHigh,
      ),
      trackOutlineColor: WidgetStatePropertyAll(p.ink),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(p.onAccent),
      side: BorderSide(color: p.ink, width: 2),
      shape: square,
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(p.text)),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.dark ? p.accent : p.ink,
      linearTrackColor: p.ink.withValues(alpha: 0.12),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, border: Border.all(color: p.ink)),
      textStyle: TextStyle(fontFamily: kBodyFont, color: p.background, fontSize: 12, fontWeight: FontWeight.w700),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.text,
      unselectedLabelColor: p.muted,
      indicatorColor: p.ink,
      labelStyle: const TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w800),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
