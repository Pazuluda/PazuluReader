import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// What the engine knows about one reader of the current chapter.
enum ReaderOptionStatus {
  /// Pages validated in this session or a FULL_READER diagnostic.
  verified,

  /// Real connector, not checked yet for this chapter.
  unverified,

  /// Tried and rejected (error, paywall, incomplete…).
  failed,

  /// Local CBZ copy.
  offline,

  /// Publisher link only: no integrable pages.
  external,

  /// Same number, uncertain edition: user confirmation required.
  needsConfirmation,
}

class ReaderOption {
  const ReaderOption({
    required this.index,
    required this.sourceName,
    required this.lang,
    required this.status,
    this.group,
    this.detail,
  });

  final int index;
  final String sourceName;
  final String lang;
  final String? group;
  final ReaderOptionStatus status;
  final String? detail;
}

/// « Lecteur 1 / Lecteur 2 / Lecteur 3 » — real sources only. With a single
/// source the bar stays visible and offers « Rechercher une autre source »
/// instead of inventing readers 2 and 3.
class ReaderSwitcher extends StatelessWidget {
  const ReaderSwitcher({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.onSetDefault,
    this.onSearchAlternatives,
    this.onConfirm,
    this.searching = false,
    this.note,
  });

  final List<ReaderOption> options;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback? onSearchAlternatives;
  final ValueChanged<int>? onConfirm;
  final bool searching;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final single = options.length <= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.md, vertical: 6),
            children: [
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(right: PazuluSpace.sm),
                  child: _ReaderPill(
                    option: o,
                    selected: o.index == selected,
                    onTap: () => o.status == ReaderOptionStatus.needsConfirmation &&
                            onConfirm != null
                        ? onConfirm!(o.index)
                        : onSelect(o.index),
                  ),
                ),
              _SmallAction(
                icon: Icons.push_pin_outlined,
                label: 'Par défaut',
                tooltip: 'Toujours ouvrir cette œuvre avec ce lecteur',
                onTap: options.isEmpty ? null : onSetDefault,
              ),
              if (onSearchAlternatives != null)
                _SmallAction(
                  icon: Icons.travel_explore_rounded,
                  label: searching ? 'Recherche…' : 'Rechercher une autre source',
                  tooltip: 'Chercher ce même chapitre dans les autres connecteurs '
                      '(métadonnées uniquement)',
                  onTap: searching ? null : onSearchAlternatives,
                  busy: searching,
                ),
            ],
          ),
        ),
        if (note != null || single)
          Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.md, 0, PazuluSpace.md, 6),
            child: Text(
              note ?? 'Un seul lecteur connu pour ce chapitre. « Rechercher une '
                  'autre source » interroge les autres connecteurs actifs.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ReaderPill extends StatelessWidget {
  const _ReaderPill({required this.option, required this.selected, required this.onTap});

  final ReaderOption option;
  final bool selected;
  final VoidCallback onTap;

  (IconData, Color, String) _status(PazuluPalette p) => switch (option.status) {
        ReaderOptionStatus.verified =>
          (Icons.verified_rounded, const Color(0xFF4ADE80), 'Pages vérifiées'),
        ReaderOptionStatus.unverified =>
          (Icons.help_outline_rounded, p.muted, 'Disponibilité non vérifiée'),
        ReaderOptionStatus.failed =>
          (Icons.error_outline_rounded, const Color(0xFFF87171), 'Indisponible ou incomplet'),
        ReaderOptionStatus.offline =>
          (Icons.download_done_rounded, p.bright, 'Copie hors ligne'),
        ReaderOptionStatus.external =>
          (Icons.link_rounded, p.muted, 'Lien éditeur, pas de pages intégrées'),
        ReaderOptionStatus.needsConfirmation =>
          (Icons.rule_rounded, const Color(0xFFFBBF24), 'Édition à confirmer'),
      };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (icon, color, statusLabel) = _status(p);
    final subtitle = [
      option.sourceName,
      option.lang.toUpperCase(),
      if (option.group != null && option.group!.isNotEmpty &&
          option.group != option.sourceName) option.group!,
    ].join(' · ');
    return Tooltip(
      message: '$statusLabel${option.detail == null ? '' : '\n${option.detail}'}',
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Lecteur ${option.index + 1}, $subtitle, $statusLabel',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PazuluRadius.sm + 4),
            child: AnimatedContainer(
              duration: PazuluMotion.of(context, PazuluMotion.hover),
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? p.primary.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(PazuluRadius.sm + 4),
                border: Border.all(
                  color: selected ? p.bright : p.borderStrong,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lecteur ${option.index + 1}',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 13)),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.tooltip,
    this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: PazuluSpace.xs),
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onTap,
          icon: busy
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}
