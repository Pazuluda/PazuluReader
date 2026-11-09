import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../design/theme.dart';
import '../app_scope.dart';
import '../format.dart';
import 'common.dart';

/// « Nouvelle version » : notes de version, taille, puis téléchargement et
/// installation (Pazulu redémarre tout seul). Style Kiosque.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final info = app.availableUpdate;
    final progress = app.updateProgress;
    final busy = progress != null;

    Widget body;
    if (info == null) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(app.checkingUpdate ? 'Recherche d’une nouvelle version…' : 'Pazulu Reader $appVersion est à jour.',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (app.updateError != null) ...[
          const SizedBox(height: 8),
          Text(app.updateError!, style: TextStyle(color: p.danger, fontSize: 13)),
        ],
        if (!app.updatesConfigured) ...[
          const SizedBox(height: 8),
          Text('Aucun dépôt GitHub de mises à jour n’est encore configuré (Réglages › Mises à jour).',
              style: TextStyle(color: p.muted, fontSize: 13)),
        ],
      ]);
    } else {
      final size = info.size > 0 ? ' · ${(info.size / (1024 * 1024)).toStringAsFixed(1)} Mo' : '';
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Tag('v$appVersion'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded, color: p.text, size: 20),
          ),
          Sticker('v${info.version}', size: 14),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '${info.publishedAt == null ? '' : 'Publiée ${relativeTime(info.publishedAt!)}'}$size',
              style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: PazuluSpace.md),
        Text('NOUVEAUTÉS', style: kiosqueDisplay(14, color: p.text)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.background, border: Border.all(color: p.ink, width: 2)),
            child: SingleChildScrollView(
              child: SelectableText(
                info.notes.isEmpty ? 'Pas de notes pour cette version.' : info.notes,
                style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: PazuluSpace.md),
        if (progress != null) ...[
          Text(progress >= 1 ? 'INSTALLATION… PAZULU VA REDÉMARRER' : 'TÉLÉCHARGEMENT ${(progress * 100).round()} %',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(height: 6),
          InkBar(value: progress, height: 14),
        ] else
          Text('Ta bibliothèque, ta progression et tes réglages sont conservés. '
              'Pazulu se ferme, se met à jour et se relance tout seul.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
        if (app.updateError != null && !busy) ...[
          const SizedBox(height: 8),
          Text(app.updateError!, style: TextStyle(color: p.danger, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ]);
    }

    return AlertDialog(
      title: Row(children: [
        Transform.rotate(
          angle: -0.06,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: kiosqueBox(p, color: p.accent, shadow: 3, width: 2),
            child: Icon(Icons.system_update_alt_rounded, color: p.onAccent, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(info == null ? 'MISES À JOUR' : 'NOUVELLE VERSION')),
      ]),
      content: SizedBox(width: 520, child: body),
      actions: [
        if (!busy)
          GhostButton(
            label: info == null ? 'Fermer' : 'Plus tard',
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (info == null && !busy && app.updatesConfigured)
          GlowButton(
            label: app.checkingUpdate ? 'Recherche…' : 'Vérifier',
            icon: Icons.refresh_rounded,
            onPressed: app.checkingUpdate ? null : app.checkForAppUpdate,
          ),
        if (info != null && !busy)
          GlowButton(
            label: 'Installer v${info.version}',
            icon: Icons.download_rounded,
            onPressed: app.installAppUpdate,
          ),
      ],
    );
  }
}
