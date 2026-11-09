import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'widgets/common.dart';
import 'widgets/entry_actions.dart';
import 'widgets/motion.dart';
import 'work_page.dart';

enum _Sort { recent, unread, release, title, added, status }

const _sortLabels = {
  _Sort.recent: 'Lu récemment',
  _Sort.unread: 'Le plus de non lus',
  _Sort.release: 'Dernière sortie',
  _Sort.title: 'Titre (A → Z)',
  _Sort.added: 'Ajout récent',
  _Sort.status: 'Statut',
};

/// Un seul filtre actif à la fois : Tout, Favoris, ou un statut.
class _Filter {
  const _Filter(this.label, {this.status, this.favorites = false});

  final String label;
  final TrackStatus? status;
  final bool favorites;
}

final _filters = <_Filter>[
  const _Filter('Tout'),
  const _Filter('Favoris', favorites: true),
  for (final s in TrackStatus.values) _Filter(s.label, status: s),
];

enum _Quick { fr, en, behind, upToDate }

const _quickLabels = {
  _Quick.fr: 'FR',
  _Quick.en: 'EN',
  _Quick.behind: 'En retard',
  _Quick.upToDate: 'À jour',
};

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _filter = 0;
  _Sort _sort = _Sort.recent;
  String _query = '';
  final Set<_Quick> _quick = {};
  final _scroll = ScrollController();
  final _search = TextEditingController();

  /// Multi-selection (null = off).
  Set<String>? _selection;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _importFiles(BuildContext context) async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['cbz', 'zip'],
        dialogTitle: 'Importer des chapitres (.cbz / .zip)',
      );
      final paths = result?.files.map((f) => f.path).whereType<String>().toList() ?? const <String>[];
      if (paths.isEmpty) return;
      final n = await app.importLocalFiles(paths);
      messenger.showSnackBar(SnackBar(content: Text('${paths.length} fichier(s) importé(s) dans $n œuvre(s).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import impossible : $e')));
    }
  }

  bool _matches(LibraryEntry e, _Filter f) {
    if (f.favorites && !e.favorite) return false;
    if (f.status != null && e.status != f.status) return false;
    return true;
  }

  static bool _hasLang(LibraryEntry e, String lang) =>
      e.latestKnown.containsKey(lang) || e.work.languages.contains(lang) ||
      e.progress.lastLang == lang;

  bool _quickMatch(LibraryEntry e, int unread) {
    if (_quick.contains(_Quick.fr) && !_hasLang(e, 'fr')) return false;
    if (_quick.contains(_Quick.en) && !_hasLang(e, 'en')) return false;
    if (_quick.contains(_Quick.behind) && unread <= 0) return false;
    if (_quick.contains(_Quick.upToDate) && (unread > 0 || e.progress.lastKey == null)) return false;
    return true;
  }

  static DateTime _lastRelease(LibraryEntry e, Map<String, DateTime> fromUpdates) {
    var best = fromUpdates[e.work.id] ?? DateTime(2000);
    for (final list in e.releaseDates.values) {
      if (list.isEmpty) continue;
      final d = DateTime.tryParse(list.first);
      if (d != null && d.isAfter(best)) best = d;
    }
    return best;
  }

  void _toggleSelect(String id) {
    setState(() {
      final sel = _selection ?? <String>{};
      if (!sel.remove(id)) sel.add(id);
      _selection = sel;
    });
  }

  Future<void> _bulk(BuildContext context, String action, {TrackStatus? status}) async {
    final app = AppScope.read(context);
    final ids = (_selection ?? const <String>{}).toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'status':
        for (final id in ids) {
          app.updateEntry(id, (e) => e.status = status!);
        }
        messenger.showSnackBar(SnackBar(content: Text('${ids.length} œuvre(s) → ${status!.label}')));
      case 'favorite':
        for (final id in ids) {
          app.updateEntry(id, (e) => e.favorite = true);
        }
        messenger.showSnackBar(SnackBar(content: Text('${ids.length} œuvre(s) ajoutée(s) aux favoris')));
      case 'remove':
        final removed = [for (final id in ids) app.removeWithUndo(id)].whereType<(LibraryEntry, List<UpdateItem>)>().toList();
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('${removed.length} œuvre(s) retirée(s) de la bibliothèque'),
          action: SnackBarAction(label: 'Annuler', onPressed: () {
            for (final r in removed) {
              app.restoreEntry(r);
            }
          }),
        ));
    }
    setState(() => _selection = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final all = app.entries.toList();
    final f = _filters[_filter];

    final unseenByWork = <String, int>{};
    final releasedAt = <String, DateTime>{};
    for (final u in app.updates) {
      if (!u.seen) unseenByWork[u.workId] = (unseenByWork[u.workId] ?? 0) + 1;
      final old = releasedAt[u.workId];
      if (old == null || u.releasedAt.isAfter(old)) releasedAt[u.workId] = u.releasedAt;
    }
    final unread = {for (final e in all) e.work.id: app.unreadCount(e)};

    final list = all.where((e) {
      if (!_matches(e, f)) return false;
      if (!_quickMatch(e, unread[e.work.id] ?? 0)) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.work.title.toLowerCase().contains(q) ||
          e.work.altTitles.any((t) => t.toLowerCase().contains(q)) ||
          e.work.authors.any((t) => t.toLowerCase().contains(q));
    }).toList();

    switch (_sort) {
      case _Sort.recent:
        list.sort((a, b) => (b.progress.updatedAt ?? b.addedAt).compareTo(a.progress.updatedAt ?? a.addedAt));
      case _Sort.unread:
        list.sort((a, b) => (unread[b.work.id] ?? 0).compareTo(unread[a.work.id] ?? 0));
      case _Sort.release:
        list.sort((a, b) => _lastRelease(b, releasedAt).compareTo(_lastRelease(a, releasedAt)));
      case _Sort.title:
        list.sort((a, b) => a.work.title.toLowerCase().compareTo(b.work.title.toLowerCase()));
      case _Sort.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _Sort.status:
        list.sort((a, b) {
          final c = a.status.index.compareTo(b.status.index);
          return c != 0 ? c : a.work.title.toLowerCase().compareTo(b.work.title.toLowerCase());
        });
    }

    final selecting = _selection != null;
    final selection = _selection ?? const <String>{};

    final grid = CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.md),
            child: Row(
              children: [
                PageTitle('Ma pile', kicker: 'Bibliothèque', size: 40),
                const SizedBox(width: 12),
                Tag('${all.length}'),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Titre, titre alternatif, auteur…',
                          isDense: true,
                          suffixIcon: _query.isEmpty ? null : IconButton(
                            tooltip: 'Effacer',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: selecting ? 'Terminer la sélection' : 'Sélectionner plusieurs œuvres',
                  icon: Icon(selecting ? Icons.close_rounded : Icons.checklist_rounded,
                      color: selecting ? p.bright : p.text),
                  onPressed: () => setState(() => _selection = selecting ? null : <String>{}),
                ),
                IconButton(
                  tooltip: 'Importer des fichiers .cbz / .zip',
                  icon: Icon(Icons.file_open_outlined, color: p.text),
                  onPressed: () => _importFiles(context),
                ),
                PopupMenuButton<_Sort>(
                  tooltip: 'Trier : ${_sortLabels[_sort]}',
                  icon: Icon(Icons.sort_rounded, color: p.text),
                  initialValue: _sort,
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: (_) => [
                    for (final e in _sortLabels.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final count = all.where((e) => _matches(e, _filters[i])).length;
                return FilterPill(
                  label: _filters[i].label,
                  count: count,
                  selected: i == _filter,
                  onTap: () => setState(() => _filter = i),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.sm, PazuluSpace.lg, 0),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Icon(Icons.tune_rounded, size: 16, color: p.muted),
              for (final q in _Quick.values)
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_quickLabels[q]!),
                  selected: _quick.contains(q),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _quick.add(q);
                      // Opposite filters cannot be on together.
                      if (q == _Quick.behind) _quick.remove(_Quick.upToDate);
                      if (q == _Quick.upToDate) _quick.remove(_Quick.behind);
                    } else {
                      _quick.remove(q);
                    }
                  }),
                ),
              Text('  Trié par : ${_sortLabels[_sort]!.toLowerCase()} · ${list.length} affichée(s)',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: all.isEmpty ? 'Votre bibliothèque est vide' : 'Aucune œuvre pour ces filtres',
              message: all.isEmpty ? 'Ajoutez des œuvres depuis l\'onglet Découvrir.' : null,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg,
                selecting ? 96 : PazuluSpace.lg),
            sliver: SliverGrid.builder(
              gridDelegate: coverGridDelegate(app.settings.gridColumns),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                final n = unread[e.work.id] ?? 0;
                final unseen = unseenByWork[e.work.id] ?? 0;
                final badge = n > 0 ? '+$n' : (unseen > 0 ? '+$unseen' : null);
                return FadeSlideIn(
                  key: ValueKey('lib-${e.work.id}-$_filter'),
                  index: i < 24 ? i : 24,
                  child: EntryContextMenu(
                    entry: selecting ? null : e,
                    child: WorkCard(
                      work: e.work,
                      heroTag: 'lib-${e.work.id}',
                      badge: badge,
                      progress: progressOf(e),
                      subtitle: n > 0 ? '${progressLabel(e)} · $n non lu${n > 1 ? 's' : ''}' : progressLabel(e),
                      selected: selecting ? selection.contains(e.work.id) : null,
                      corner: selecting ? null : EntryMenuButton(entry: e),
                      hoverInfo: selecting ? null : workPreview(e.work,
                          status: e.status.label, unread: n),
                      onTap: selecting
                          ? () => _toggleSelect(e.work.id)
                          : () => pushPage(context, WorkPage(work: e.work, heroTag: 'lib-${e.work.id}')),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: selecting ? null : ScrollToTopButton(controller: _scroll),
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: grid),
          if (selecting)
            Positioned(
              left: PazuluSpace.lg, right: PazuluSpace.lg, bottom: PazuluSpace.lg,
              child: Glass(
                highlight: true,
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${selection.length} sélectionnée(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () => setState(() => _selection = {for (final e in list) e.work.id}),
                    child: const Text('Tout sélectionner'),
                  ),
                  PopupMenuButton<TrackStatus>(
                    enabled: selection.isNotEmpty,
                    tooltip: 'Changer le statut',
                    onSelected: (s) => _bulk(context, 'status', status: s),
                    itemBuilder: (_) => [
                      for (final s in TrackStatus.values)
                        if (s != TrackStatus.discover) PopupMenuItem(value: s, child: Text(s.label)),
                    ],
                    child: const Chip(avatar: Icon(Icons.flag_outlined, size: 18), label: Text('Statut')),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.favorite_border_rounded, size: 18),
                    label: const Text('Favoris'),
                    onPressed: selection.isEmpty ? null : () => _bulk(context, 'favorite'),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.delete_outline_rounded, size: 18, color: p.danger),
                    label: const Text('Retirer'),
                    onPressed: selection.isEmpty ? null : () => _bulk(context, 'remove'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selection = null),
                    child: const Text('Annuler'),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Pastille de filtre animée (sélection unique).
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = PazuluMotion.of(context, PazuluMotion.hover);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: d,
            curve: PazuluMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? p.ink : p.surface,
              border: Border.all(color: p.ink, width: 2.5),
            ),
            transform: Matrix4.rotationZ(selected ? -0.02 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: selected ? p.background : p.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(color: selected ? p.background.withValues(alpha: 0.7) : p.muted, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
