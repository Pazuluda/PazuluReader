import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../design/theme.dart';
import '../app_scope.dart';
import '../work_page.dart';

/// Bandeaux discrets en haut de la bibliothèque : doublons à fusionner,
/// séries terminées avec des chapitres restants, lectures à mettre en
/// pause. Calculés une fois par changement de données (pas à chaque
/// image), masquables.
class LibraryHints extends StatefulWidget {
  const LibraryHints({super.key});

  @override
  State<LibraryHints> createState() => _LibraryHintsState();
}

class _LibraryHintsState extends State<LibraryHints> {
  int _rev = -1;
  List<(LibraryEntry, LibraryEntry)> _dups = const [];
  List<LibraryEntry> _finished = const [];
  List<LibraryEntry> _stale = const [];
  bool _hideFinished = false;
  DateTime _at = DateTime(2000);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Recomputed at most every 5 s while background work changes the data
    // (never at every refresh: no load on big libraries).
    if (_rev != app.revision && DateTime.now().difference(_at) > const Duration(seconds: 5)) {
      _rev = app.revision;
      _at = DateTime.now();
      _dups = app.duplicateEntries;
      _finished = app.finishedWithChaptersLeft;
      _stale = app.staleReadings;
    }
    final p = context.pal;
    final banners = <Widget>[];
    Widget banner(IconData icon, String text, List<Widget> actions) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.borderStrong)),
          child: Row(children: [
            Icon(icon, size: 18, color: p.bright),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            ...actions,
          ]),
        );
    if (_dups.isNotEmpty) {
      banners.add(banner(Icons.content_copy_rounded,
          '${_dups.length} doublon(s) possible(s) : la même œuvre sous deux fiches.',
          [TextButton(onPressed: () => _showDuplicates(context), child: const Text('Voir'))]));
    }
    if (_finished.isNotEmpty && !_hideFinished) {
      banners.add(banner(Icons.flag_rounded,
          '${_finished.length} série(s) terminée(s) où il te reste des chapitres : '
          '${_finished.take(3).map((e) => e.work.title).join(', ')}${_finished.length > 3 ? '…' : ''}',
          [
            TextButton(onPressed: () => _showList(context, 'Séries terminées à finir', _finished), child: const Text('Voir')),
            IconButton(tooltip: 'Masquer', icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _hideFinished = true)),
          ]));
    }
    if (_stale.isNotEmpty) {
      banners.add(banner(Icons.pause_circle_outline_rounded,
          '${_stale.length} lecture(s) « en cours » pas ouvertes depuis 3 mois. Les mettre en pause ?',
          [
            TextButton(onPressed: () => _showList(context, 'Pas ouvertes depuis 3 mois', _stale), child: const Text('Voir')),
            TextButton(
              onPressed: () {
                _at = DateTime(2000);
                final app = AppScope.read(context);
                app.pauseAll(_stale);
                app.dismissPauseHint();
              },
              child: const Text('Tout en pause'),
            ),
            IconButton(tooltip: 'Plus tard', icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _at = DateTime(2000);
                  AppScope.read(context).dismissPauseHint();
                }),
          ]));
    }
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: banners);
  }

  void _showList(BuildContext context, String title, List<LibraryEntry> list) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          height: 420,
          child: ListView(children: [
            for (final e in list)
              ListTile(
                dense: true,
                title: Text(e.work.title),
                subtitle: Text('${AppScope.read(context).unreadCount(e)} non lu(s)'),
                onTap: () {
                  Navigator.pop(ctx);
                  pushPage(context, WorkPage(work: e.work, heroTag: 'hint-${e.work.id}'));
                },
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  void _showDuplicates(BuildContext context) {
    // After the dialog (merges, ignored pairs): banners recomputed at once.
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) {
        final app = AppScope.read(context);
        final dups = app.duplicateEntries;
        String info(LibraryEntry e) =>
            '${e.progress.readKeys.length} lu(s) · ${e.work.links.length} site(s)'
            '${e.progress.lastKey == null ? '' : ' · ch. ${e.progress.lastKey}'}';
        return AlertDialog(
          title: const Text('Doublons possibles'),
          content: SizedBox(
            width: 620,
            height: 460,
            child: dups.isEmpty
                ? const Center(child: Text('Plus aucun doublon.'))
                : ListView(children: [
                    for (final (a, b) in dups)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('« ${a.work.title} »  ·  ${info(a)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('« ${b.work.title} »  ·  ${info(b)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 8, children: [
                              FilledButton.tonal(
                                onPressed: () {
                                  app.mergeEntries(a, b);
                                  refresh(() {});
                                },
                                child: Text('Fusionner (garder « ${_short(a.work.title)} »)'),
                              ),
                              FilledButton.tonal(
                                onPressed: () {
                                  app.mergeEntries(b, a);
                                  refresh(() {});
                                },
                                child: Text('Fusionner (garder « ${_short(b.work.title)} »)'),
                              ),
                              TextButton(
                                onPressed: () {
                                  app.ignoreDuplicate(a, b);
                                  refresh(() {});
                                },
                                child: const Text('Pas la même œuvre'),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        );
      }),
    ).then((_) {
      if (mounted) setState(() => _at = DateTime(2000));
    });
  }

  static String _short(String t) => t.length > 28 ? '${t.substring(0, 27)}…' : t;
}
