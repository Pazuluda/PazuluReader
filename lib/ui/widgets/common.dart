import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../../core/chapter_key.dart';
import '../../core/models.dart';
import '../../core/sources/mangadex.dart';
import '../../design/theme.dart';
import 'motion.dart';

/// Couverture réseau avec place réservée (pas de saut de mise en page),
/// pulsation pendant le chargement et repli en cas d'erreur.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url, this.radius = PazuluRadius.card, this.ratio = 2 / 3});

  final String? url;
  final double radius;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.surfaceHigh, p.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.auto_stories_outlined, color: p.muted),
    );
    final u = url;
    // Kiosque : couverture cernée d'un trait d'encre.
    return Container(
      decoration: BoxDecoration(border: Border.all(color: p.ink, width: 2)),
      child: AspectRatio(
        aspectRatio: ratio,
        child: u == null
            ? fallback
            : LayoutBuilder(
                builder: (context, c) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  // Decode size in steps of 120 px: a resize or a hero
                  // animation does not decode the cover again at every pixel.
                  final raw = (c.maxWidth.isFinite ? c.maxWidth : 200) * dpr;
                  final w = ((raw / 120).ceil() * 120).clamp(120, 960);
                  if (u.startsWith('file:')) {
                    return Image.file(
                      File(Uri.parse(u).toFilePath()),
                      fit: BoxFit.cover,
                      cacheWidth: w,
                      errorBuilder: (context, error, stack) => fallback,
                    );
                  }
                  return _NetworkCover(
                    url: u,
                    width: w,
                    fallback: fallback,
                  );
                },
              ),
      ),
    );
  }
}

/// Network cover with the headers sites expect for their images (many
/// refuse a cover without the page's origin as Referer) and one automatic
/// new attempt after a failure (busy CDN, connection cut).
class _NetworkCover extends StatefulWidget {
  const _NetworkCover({required this.url, required this.width, required this.fallback});

  final String url;
  final int width;
  final Widget fallback;

  @override
  State<_NetworkCover> createState() => _NetworkCoverState();
}

class _NetworkCoverState extends State<_NetworkCover> {
  int _attempt = 0;
  Timer? _retry;

  @override
  void didUpdateWidget(_NetworkCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _retry?.cancel();
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Map<String, String> get _headers {
    final uri = Uri.tryParse(widget.url);
    return {
      'User-Agent': MangaDexSource.userAgent,
      'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8',
      if (uri != null && uri.hasAuthority) 'Referer': '${uri.scheme}://${uri.host}/',
    };
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.url;
    final w = widget.width;
    final fallback = widget.fallback;
    return Image.network(
                    // Same address (signed CDN links must not change): a failed
                    // image is not kept in Flutter's cache, the new key reloads it.
                    u,
                    key: ValueKey('$u#$_attempt'),
                    headers: _headers,
                    fit: BoxFit.cover,
                    cacheWidth: w,
                    // No AnimatedSwitcher here: it kept the PREVIOUS image on
                    // screen during its fade while Flutter had already
                    // released it -> « Cannot clone a disposed image » in the
                    // middle of a frame = black screen. The fade only changes
                    // the opacity of the CURRENT image.
                    frameBuilder: (context, child, frame, sync) {
                      if (sync) return child;
                      return Stack(fit: StackFit.expand, children: [
                        if (frame == null) const Pulse(radius: 0),
                        AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: PazuluMotion.of(context, const Duration(milliseconds: 260)),
                          child: child,
                        ),
                      ]);
                    },
                    errorBuilder: (context, error, stack) {
                      if (_attempt == 0 && _retry == null) {
                        _retry = Timer(const Duration(seconds: 4), () {
                          if (mounted) setState(() => _attempt = 1);
                        });
                      }
                      return fallback;
                    },
                  );
  }
}

/// Pastille de langue (EN, FR…) : FR sur l'accent, EN en négatif.
class LangBadge extends StatelessWidget {
  const LangBadge(this.lang, {super.key, this.dimmed = false});

  final String lang;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fr = lang == 'fr';
    final bg = dimmed ? p.surfaceHigh : (fr ? p.accent : p.ink);
    final fg = dimmed ? p.muted : (fr ? p.onAccent : p.background);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: bg, border: Border.all(color: p.ink, width: 1.5)),
      child: Text(
        lang.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: fg),
      ),
    );
  }
}

/// Étiquette carrée, majuscules (« tampon »).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = color;
    // Une couleur donnée = fond plein (lisible : texte encre ou papier).
    final bg = c == null ? p.surface : c;
    final fg = c == null
        ? p.text
        : (ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF111111));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, border: Border.all(color: p.ink, width: 2)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Encadré « Kiosque » : trait épais + ombre décalée pleine.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PazuluSpace.md),
    this.radius = PazuluRadius.card,
    this.highlight = false,
    this.shadow = 5,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool highlight;
  final double shadow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: padding,
      decoration: kiosqueBox(p, color: color ?? (highlight ? p.selected : p.surface), shadow: shadow),
      child: child,
    );
  }
}

/// Boîte cliquable à ombre décalée : se soulève au survol, s'écrase au clic.
class PressableBox extends StatefulWidget {
  const PressableBox({super.key, required this.child, this.onTap, this.color, this.shadow = 4});

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final double shadow;

  @override
  State<PressableBox> createState() => _PressableBoxState();
}

class _PressableBoxState extends State<PressableBox> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = widget.onTap != null;
    final lift = !enabled ? 0.0 : (_down ? -widget.shadow : (_hover ? 1.5 : 0.0));
    final sh = widget.shadow + lift;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PazuluMotion.of(context, const Duration(milliseconds: 90)),
          transform: Matrix4.translationValues(-lift, -lift, 0),
          decoration: kiosqueBox(p, color: widget.color, shadow: sh < 0 ? 0 : sh),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Bouton principal : fond accent, trait d'encre, ombre décalée.
class GlowButton extends StatelessWidget {
  const GlowButton({super.key, required this.label, required this.onPressed, this.icon, this.big = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null;
    final fg = enabled ? p.onAccent : p.muted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: PressableBox(
        onTap: onPressed,
        shadow: enabled ? 3 : 0,
        color: enabled ? p.accent : p.surfaceHigh,
        child: SizedBox(
          height: big ? 50 : 42,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: big ? 22 : 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(
                  label.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, letterSpacing: 0.4,
                      fontSize: big ? 14.5 : 13),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton secondaire : papier, trait d'encre, ombre décalée.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: PressableBox(
        onTap: onPressed,
        shadow: enabled ? 3 : 0,
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: enabled ? p.text : p.muted),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(
                  label.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: enabled ? p.text : p.muted, fontWeight: FontWeight.w800,
                      letterSpacing: 0.4, fontSize: 13),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing, this.padding});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.md, PazuluSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: kiosqueDisplay(21, color: p.text)),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(subtitle!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Titre de page « Kiosque » : petite ligne de contexte + grand titre.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.kicker, this.size = 46});

  final String title;
  final String? kicker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null)
          Text(kicker!.toUpperCase(),
              style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        Text(title.toUpperCase(), style: kiosqueDisplay(size, color: p.text)),
      ],
    );
  }
}

/// Autocollant penché (« +7 », « REPRENDRE »).
class Sticker extends StatelessWidget {
  const Sticker(this.text, {super.key, this.angle = -0.1, this.size = 12});

  final String text;
  final double angle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: p.accent,
          border: Border.all(color: const Color(0xFF111111), width: 2),
        ),
        child: Text(text.toUpperCase(), style: kiosqueDisplay(size, color: p.onAccent)),
      ),
    );
  }
}

/// Barre de progression cernée (Kiosque).
class InkBar extends StatelessWidget {
  const InkBar({super.key, required this.value, this.height = 10});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: height,
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.ink, width: 2)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth * value.clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: PazuluMotion.of(context, const Duration(milliseconds: 500)),
            curve: PazuluMotion.curve,
            width: w,
            decoration: BoxDecoration(
              color: p.accent,
              border: w > 2 && w < c.maxWidth - 1 ? Border(right: BorderSide(color: p.ink, width: 2)) : null,
            ),
          ),
        );
      }),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = Theme.of(context).textTheme;
    return FadeSlideIn(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg, vertical: PazuluSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -0.06,
              child: Container(
                width: 76,
                height: 76,
                decoration: kiosqueBox(p, color: p.accent, shadow: 4),
                child: Icon(icon, size: 34, color: p.onAccent),
              ),
            ),
            const SizedBox(height: PazuluSpace.lg),
            Text(title.toUpperCase(), style: kiosqueDisplay(20, color: p.text), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: PazuluSpace.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(message!, style: t.bodyMedium?.copyWith(color: p.muted), textAlign: TextAlign.center),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: PazuluSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Chargement impossible',
      message: error.toString(),
      action: onRetry == null ? null : GlowButton(label: 'Réessayer', icon: Icons.refresh, onPressed: onRetry),
    );
  }
}

/// Carte de couverture pour les grilles et étagères.
class WorkCard extends StatelessWidget {
  const WorkCard({
    super.key,
    required this.work,
    required this.heroTag,
    required this.onTap,
    this.subtitle,
    this.progress,
    this.badge,
    this.corner,
    this.hoverInfo,
    this.selected,
  });

  final WorkInfo work;
  final String heroTag;
  final VoidCallback onTap;
  final String? subtitle;

  /// Small button in the top-right corner of the cover (« ⋯ », « + »).
  final Widget? corner;

  /// Shown when the mouse rests on the cover (summary, status, sites…).
  final String? hoverInfo;

  /// Multi-selection: null = not selecting, else the check state.
  final bool? selected;

  /// Avancement 0..1, affiché sous la couverture.
  final double? progress;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: work.title,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoverLift(
                child: Stack(
                  children: [
                    if (hoverInfo == null)
                      Hero(tag: heroTag, child: CoverImage(url: work.coverUrl))
                    else
                      Tooltip(
                        message: hoverInfo!,
                        waitDuration: const Duration(milliseconds: 450),
                        preferBelow: false,
                        constraints: const BoxConstraints(maxWidth: 340),
                        padding: const EdgeInsets.all(12),
                        textStyle: TextStyle(color: p.text, fontSize: 12.5, height: 1.4),
                        decoration: kiosqueBox(p, shadow: 5),
                        child: Hero(tag: heroTag, child: CoverImage(url: work.coverUrl)),
                      ),
                    if (selected != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: selected! ? p.accent.withValues(alpha: 0.35) : Colors.black26,
                              border: Border.all(color: selected! ? p.ink : Colors.transparent, width: 4),
                            ),
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.all(8),
                            child: Icon(selected! ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                color: selected! ? p.ink : Colors.white, size: 28),
                          ),
                        ),
                      )
                    else if (corner != null)
                      Positioned(top: 6, right: 6, child: corner!),
                    if (badge != null)
                      Positioned(top: 8, left: 6, child: Sticker(badge!)),
                    if (progress != null)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: InkBar(value: progress!, height: 8),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.25, color: p.text),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.muted, letterSpacing: 0.2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de couvertures adaptative (colonnes auto ou imposées).
SliverGridDelegate coverGridDelegate(int columns) {
  if (columns > 0) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      childAspectRatio: 0.5,
      mainAxisSpacing: PazuluSpace.md,
      crossAxisSpacing: PazuluSpace.md,
    );
  }
  return const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 176,
    childAspectRatio: 0.5,
    mainAxisSpacing: PazuluSpace.md,
    crossAxisSpacing: PazuluSpace.md,
  );
}

String workSubtitle(WorkInfo w) {
  final langs = w.languages.where((l) => l == 'en' || l == 'fr').map((l) => l.toUpperCase());
  return [w.type.label, if (langs.isNotEmpty) langs.join(' · ')].join(' · ');
}

/// Avancement approximatif d'une œuvre (dernier chapitre lu / dernier connu).
double? progressOf(LibraryEntry e) {
  final last = e.progress.lastKey;
  if (last == null) return null;
  final current = ChapterKey.parse(last).number;
  final latest = e.latestKnown.values.fold<double>(0, (m, v) => v > m ? v : m);
  if (current == null || latest <= 0) return null;
  return (current / latest).clamp(0.0, 1.0);
}

/// Libellé « Ch. 12 · p. 5 » de la position enregistrée.
String progressLabel(LibraryEntry e) {
  final p = e.progress;
  if (p.lastKey == null) return e.status.label;
  final key = ChapterKey.parse(p.lastKey);
  if (p.readKeys.contains(key.id)) return '${key.label} terminé';
  return '${key.label} · p. ${p.lastPage + 1}';
}

/// Text of the preview shown when the mouse rests on a cover.
String workPreview(WorkInfo w, {String? status, int? sites, int? unread}) {
  final head = [
    w.type.label,
    if (w.year != null) '${w.year}',
    if (status != null) status,
    if (w.lastChapter != null) '${w.lastChapter} ch.',
    if (sites != null && sites > 0) '$sites site${sites > 1 ? 's' : ''}',
    if (unread != null && unread > 0) '$unread non lu${unread > 1 ? 's' : ''}',
  ].join(' · ');
  final genres = w.tags.where((t) => !t.startsWith('★')).take(4).join(', ');
  var desc = w.description.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (desc.length > 260) desc = '${desc.substring(0, 257)}…';
  return [
    w.title,
    head,
    if (genres.isNotEmpty) genres,
    if (desc.isNotEmpty) desc,
  ].join('\n');
}

/// « Retour en haut » : appears once the list has been scrolled down.
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _shown = false;

  void _listen() {
    final c = widget.controller;
    final show = c.hasClients && c.offset > 900;
    if (show != _shown && mounted) setState(() => _shown = show);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listen);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: FloatingActionButton.small(
        heroTag: null,
        tooltip: 'Retour en haut',
        onPressed: () => widget.controller.animateTo(0,
            duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic),
        child: const Icon(Icons.arrow_upward_rounded),
      ),
    );
  }
}
