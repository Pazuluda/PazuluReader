import 'package:flutter/material.dart';

import '../../design/theme.dart';

import '../../core/models.dart';
import '../app_scope.dart';
import '../read_actions.dart';
import '../work_page.dart';

/// Removes a work from the library, with « Annuler » for a wrong click
/// (One Piece added by mistake: one click, gone, and back if needed).
void removeWithUndo(BuildContext context, LibraryEntry entry) {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final removed = app.removeWithUndo(entry.work.id);
  if (removed == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 6),
    content: Text('« ${entry.work.title} » retiré de la bibliothèque'),
    action: SnackBarAction(label: 'Annuler', onPressed: () => app.restoreEntry(removed)),
  ));
}

/// Takes a work out of « En cours » (status « Abandonné »), kept in the
/// library with its progress.
void hideFromReading(BuildContext context, LibraryEntry entry) {
  final app = AppScope.read(context);
  final before = entry.status;
  app.updateEntry(entry.work.id, (e) => e.status = TrackStatus.dropped);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 6),
    content: Text('« ${entry.work.title} » retiré des lectures en cours (statut Abandonné)'),
    action: SnackBarAction(label: 'Annuler',
        onPressed: () => app.updateEntry(entry.work.id, (e) => e.status = before)),
  ));
}

enum _EntryAction { next, open, hide, favorite, remove, status }

/// The actions of a work, everywhere (right click, long press, « ⋯ »).
Future<void> showEntryMenu(BuildContext context, LibraryEntry entry, Offset position) async {
  final app = AppScope.read(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final choice = await showMenu<Object>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      const PopupMenuItem(value: _EntryAction.next, child: ListTile(dense: true,
          leading: Icon(Icons.play_arrow_rounded), title: Text('Lire le suivant'))),
      const PopupMenuItem(value: _EntryAction.open, child: ListTile(dense: true,
          leading: Icon(Icons.info_outline_rounded), title: Text('Ouvrir la fiche'))),
      PopupMenuItem(value: _EntryAction.favorite, child: ListTile(dense: true,
          leading: Icon(entry.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          title: Text(entry.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'))),
      const PopupMenuDivider(),
      for (final s in TrackStatus.values)
        if (s != TrackStatus.discover)
          PopupMenuItem(value: s, child: ListTile(dense: true,
              leading: Icon(s == entry.status ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18),
              title: Text('Statut : ${s.label}'))),
      const PopupMenuDivider(),
      if (entry.status != TrackStatus.dropped)
        const PopupMenuItem(value: _EntryAction.hide, child: ListTile(dense: true,
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Retirer des « En cours »'))),
      const PopupMenuItem(value: _EntryAction.remove, child: ListTile(dense: true,
          leading: Icon(Icons.delete_outline_rounded),
          title: Text('Supprimer de la bibliothèque'))),
    ],
  );
  if (!context.mounted || choice == null) return;
  if (choice is TrackStatus) {
    app.updateEntry(entry.work.id, (e) => e.status = choice);
    return;
  }
  switch (choice as _EntryAction) {
    case _EntryAction.next:
      await resumeInPazulu(context, entry.work);
    case _EntryAction.open:
      await pushPage(context, WorkPage(work: entry.work, heroTag: 'menu-${entry.work.id}'));
    case _EntryAction.favorite:
      app.updateEntry(entry.work.id, (e) => e.favorite = !e.favorite);
    case _EntryAction.hide:
      hideFromReading(context, entry);
    case _EntryAction.remove:
      removeWithUndo(context, entry);
    case _EntryAction.status:
      break;
  }
}

/// Small round « ⋯ » button shown on a cover.
class EntryMenuButton extends StatelessWidget {
  const EntryMenuButton({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.ink, width: 2)),
      child: Builder(builder: (context) => InkWell(
        onTapDown: (d) => showEntryMenu(context, entry, d.globalPosition),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.more_horiz_rounded, size: 18, color: p.text),
        ),
      )),
    );
  }
}

/// Wraps a card: right click and long press open the actions.
class EntryContextMenu extends StatelessWidget {
  const EntryContextMenu({super.key, required this.entry, required this.child});

  final LibraryEntry? entry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return child;
    Offset? at;
    return GestureDetector(
      onSecondaryTapDown: (d) => showEntryMenu(context, e, d.globalPosition),
      onLongPressDown: (d) => at = d.globalPosition,
      onLongPress: () => showEntryMenu(context, e, at ?? Offset.zero),
      child: child,
    );
  }
}
