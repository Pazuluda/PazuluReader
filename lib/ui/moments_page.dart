import 'package:flutter/material.dart';

import '../core/moments.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'read_actions.dart';
import 'widgets/common.dart';

/// « Mes moments » : les pages marquées dans le lecteur (touche B ou
/// bouton marque-page), à rouvrir exactement là.
class MomentsPage extends StatelessWidget {
  const MomentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final list = app.moments;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes moments')),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(PazuluSpace.lg),
                child: Text(
                  'Aucun moment pour l\'instant.\nDans le lecteur, touche B ou bouton marque-page '
                  'pour garder une scène et la retrouver ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(PazuluSpace.lg),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: PazuluSpace.sm),
              itemBuilder: (context, i) => _MomentTile(moment: list[i]),
            ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({required this.moment});

  final Moment moment;

  Future<void> _editNote(BuildContext context) async {
    final ctrl = TextEditingController(text: moment.note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note du moment'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3,
            decoration: const InputDecoration(hintText: 'Pourquoi cette scène ?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    ctrl.dispose();
    if (note != null && context.mounted) AppScope.read(context).setMomentNote(moment, note);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = moment;
    final d = m.at;
    String two(int v) => v.toString().padLeft(2, '0');
    return Material(
      color: p.surface,
      child: InkWell(
        onTap: () => resumeInPazulu(context, m.work, chapterHint: m.chapterId, exactPage: m.page),
        child: Padding(
          padding: const EdgeInsets.all(PazuluSpace.sm),
          child: Row(
            children: [
              SizedBox(width: 56, child: CoverImage(url: m.work.coverUrl)),
              const SizedBox(width: PazuluSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.work.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${m.chapterLabel} · page ${m.page + 1} · marqué le '
                        '${two(d.day)}/${two(d.month)}/${d.year}',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    if (m.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('« ${m.note} »', style: TextStyle(color: p.text, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Note',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: () => _editNote(context),
              ),
              IconButton(
                tooltip: 'Retirer ce moment',
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: () => AppScope.read(context).removeMoment(m),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
