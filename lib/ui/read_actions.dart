import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/chapter_key.dart';
import '../core/chapters.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'reader_page.dart';
import 'source_browser_page.dart';

/// One entry point for the library, release feed and source results.
/// Open a readable native/offline variant in our own HUD; never silently
/// redirect a "Lire" action to a website.
Future<void> resumeInPazulu(
  BuildContext context,
  WorkInfo work, {
  String? chapterHint,
  String? siteId,
  String? chapterUrl,
}) async {
  final app = AppScope.read(context);
  List<ChapterGroup> groups;
  try {
    groups = await app.chaptersFor(work, refresh: true);
  } catch (e) {
    groups = const <ChapterGroup>[];
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certaines sources sont indisponibles : $e')),
      );
    }
  }
  if (!context.mounted) return;
  // External chapter links are *not* images and cannot be read by ReaderPage.
  // Only native sources, session captures and existing CBZ archives qualify.
  final readable = <ChapterGroup>[
    for (final group in groups)
      if (group.variants.any(app.isPazuluRetryable))
        ChapterGroup(group.key, [
          for (final v in group.variants)
            if (app.isPazuluRetryable(v)) v,
        ]),
  ];
  if (readable.isEmpty) {
    await _missingChapterDialog(context, work, siteId: siteId, chapterUrl: chapterUrl);
    return;
  }
  final progress = app.entry(work.id)?.progress ?? ReadingProgress();
  if (chapterHint != null &&
      !readable.any((g) => g.key.id == ChapterKey.parse(chapterHint).id)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Le ch. $chapterHint est annoncé, mais pas encore disponible '
          'dans notre lecteur. Reprise au dernier chapitre accessible.'),
    ));
  }
  var (index, page) = resumePosition(readable, progress);
  // Never resume on a chapter only one site announces ahead of all the
  // others (« non confirmé »: Mythic Item Obtained « 195 » = the 194 again):
  // back to the last confirmed chapter.
  bool unconfirmed(ChapterGroup g) => g.variants.isNotEmpty &&
      g.variants.every((v) => app.isAheadUnconfirmed(work.id, v.lang, g.key.id));
  if (index >= 0 && index < readable.length && unconfirmed(readable[index])) {
    final keyNumber = readable[index].key.number;
    var best = -1;
    for (var i = 0; i < readable.length; i++) {
      final n = readable[i].key.number;
      if (unconfirmed(readable[i]) || n == null || keyNumber == null || n >= keyNumber) continue;
      if (best < 0 || n > readable[best].key.number!) best = i;
    }
    if (best >= 0) {
      index = best;
      page = 0;
    }
  }
  // New library item: start on its notified chapter if available. An existing
  // reading position always wins, regardless of source/language.
  if (progress.lastKey == null && chapterHint != null) {
    final hint = ChapterKey.parse(chapterHint).id;
    final found = readable.indexWhere((group) => group.key.id == hint);
    if (found >= 0) { index = found; page = 0; }
  }
  await pushPage(context, ReaderPage(
    work: work, groups: readable, initialIndex: index, initialPage: page,
  ));
}

Future<int> importCbzForWork(BuildContext context, WorkInfo work) async {
  final app = AppScope.read(context);
  final files = await FilePicker.platform.pickFiles(
    type: FileType.custom, allowedExtensions: const ['zip', 'cbz'],
    allowMultiple: true, dialogTitle: 'Importer des chapitres dans ${work.title}',
  );
  if (!context.mounted || files == null) return 0;
  final paths = files.files.map((f) => f.path).whereType<String>().toList();
  if (paths.isEmpty) return 0;
  var lang = app.settings.comicLangs.contains('fr')
      ? 'fr' : 'en';
  final chapterController = TextEditingController();
  try {
    final options = await showDialog<(String, String?)>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, change) => AlertDialog(
          title: Text('Associer ${paths.length} archive(s)'),
          content: SizedBox(width: 420, child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Œuvre : ${work.title}\nLes fichiers rejoindront cet historique de lecture.'),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: lang,
                decoration: const InputDecoration(labelText: 'Langue des chapitres'),
                items: const [
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                  DropdownMenuItem(value: 'en', child: Text('Anglais')),
                ],
                onChanged: (value) { if (value != null) change(() => lang = value); },
              ),
              if (paths.length == 1) ...[
                const SizedBox(height: 12),
                TextField(controller: chapterController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Chapitre (facultatif si dans le nom)',
                    hintText: 'Ex. 16 ou 115.5'),
                ),
              ],
              const SizedBox(height: 10),
              const Text('Fichiers CBZ/ZIP autorisés uniquement. '
                'Aucun contenu payant ni protection technique n’est contourné.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext,
              (lang, chapterController.text.trim().isEmpty
                  ? null : chapterController.text.trim())),
              child: const Text('Importer dans cette œuvre')),
          ],
        ),
      ),
    );
    if (!context.mounted || options == null) return 0;
    try {
      final count = await app.importArchivesForWork(
        work, paths, language: options.$1, singleChapterNumber: options.$2,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count chapitre(s) ajouté(s) à ${work.title}.')));
      }
      return count;
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import refusé : $e')));
      return 0;
    }
  } finally {
    chapterController.dispose();
  }
}

Future<void> _missingChapterDialog(
  BuildContext context, WorkInfo work, {
  String? siteId,
  String? chapterUrl,
}) async {
  final app = AppScope.read(context);
  final site = siteId == null ? null : app.siteById(siteId);
  final canInspect = site != null && chapterUrl != null &&
      site.accepts(chapterUrl) && app.extensionRecipes.forSite(site.id).canInspect;
  final action = await showDialog<String>(context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pas de chapitre lisible pour le moment'),
      content: const SizedBox(width: 420, child: Text(
        'La fiche ou le lien a été trouvé, mais aucune source connectée '
        'ne fournit actuellement les pages de ce chapitre à Pazulu. '
        'La recherche et le lecteur ne téléchargent pas de contenu '
        'inaccessible. Ajoute une source compatible ou consulte '
        'le diagnostic des sources dans la fiche.'
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Fermer')),
        if (canInspect) FilledButton(
          onPressed: () => Navigator.pop(ctx, 'inspect'),
          child: const Text('Vérifier cette source')),
      ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'inspect' && canInspect) {
    await pushPage(context, SourceBrowserPage(
      title: '${work.title} · Chapitre', url: chapterUrl,
      siteId: site.id, workId: work.id,
    ));
  }

}
