import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/site_index.dart';
import '../../design/theme.dart';
import '../app_scope.dart';
import '../read_actions.dart';
import '../work_page.dart';
import 'common.dart';

class _Item {
  const _Item(this.icon, this.title, this.subtitle, this.run, {this.coverUrl});

  final IconData icon;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final void Function(BuildContext outer) run;
}

/// Ctrl+K : one box to open any work of the library or of every site's
/// catalogue, search everywhere, or jump to a tab.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<String> tabs,
  required ValueChanged<int> goTab,
  required ValueChanged<String> searchEverywhere,
}) {
  final outer = context;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _Palette(outer: outer, tabs: tabs, goTab: goTab, searchEverywhere: searchEverywhere),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.outer, required this.tabs, required this.goTab,
      required this.searchEverywhere});

  final BuildContext outer;
  final List<String> tabs;
  final ValueChanged<int> goTab;
  final ValueChanged<String> searchEverywhere;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';
  int _cursor = 0;

  List<_Item> _items() {
    final app = AppScope.read(widget.outer);
    final q = _query.trim();
    final n = SiteTitleIndex.norm(q);
    final out = <_Item>[];
    bool hit(WorkInfo w) => n.isNotEmpty &&
        (SiteTitleIndex.norm(w.title).contains(n) ||
            w.altTitles.any((t) => SiteTitleIndex.norm(t).contains(n)));

    final mine = app.entries.toList()
      ..sort((a, b) => (b.progress.updatedAt ?? b.addedAt).compareTo(a.progress.updatedAt ?? a.addedAt));
    final libraryHits = q.isEmpty ? mine.take(5) : mine.where((e) => hit(e.work)).take(6);
    for (final e in libraryHits) {
      final unread = app.unreadCount(e);
      out.add(_Item(Icons.collections_bookmark_rounded, e.work.title,
          'Bibliothèque · ${progressLabel(e)}${unread > 0 ? ' · $unread non lu${unread > 1 ? 's' : ''}' : ''}',
          coverUrl: e.work.coverUrl,
          (ctx) => pushPage(ctx, WorkPage(work: e.work, heroTag: 'palette-${e.work.id}'))));
      if (q.isEmpty) continue;
      out.add(_Item(Icons.play_arrow_rounded, 'Reprendre « ${e.work.title} »', 'Ouvre le lecteur',
          (ctx) => resumeInPazulu(ctx, e.work)));
    }

    if (n.length >= 2) {
      final works = app.siteIndex.works;
      if (works == null) {
        app.siteIndex.prepareWorks().then((_) {
          if (mounted) setState(() {});
        });
      } else {
        final ids = {for (final e in mine) SiteTitleIndex.norm(e.work.title)};
        var count = 0;
        for (final w in works) {
          if (count >= 6) break;
          if (!w.key.contains(n) || ids.contains(w.key)) continue;
          count++;
          out.add(_Item(Icons.public_rounded, w.title,
              'Catalogue · ${w.links.length} site${w.links.length > 1 ? 's' : ''}',
              (ctx) => pushPage(ctx, WorkPage(work: w.toWork(), heroTag: 'palette-${w.key}'))));
        }
      }
      out.add(_Item(Icons.travel_explore_rounded, 'Chercher « $q » sur toutes les sources',
          'Découvrir · tous les sites', (_) => widget.searchEverywhere(q)));
    }

    for (var i = 0; i < widget.tabs.length; i++) {
      final t = widget.tabs[i];
      if (q.isNotEmpty && !SiteTitleIndex.norm(t).contains(n)) continue;
      out.add(_Item(Icons.tab_rounded, 'Aller à « $t »', 'Raccourci : ${i + 1}', (_) => widget.goTab(i)));
    }
    return out;
  }

  void _run(_Item item) {
    Navigator.of(context).pop();
    item.run(widget.outer);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = _items();
    if (_cursor >= items.length) _cursor = items.isEmpty ? 0 : items.length - 1;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: p.surface,
        elevation: 24,
        borderRadius: BorderRadius.circular(PazuluRadius.big),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    setState(() => _cursor = items.isEmpty ? 0 : (_cursor + 1) % items.length),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    setState(() => _cursor = items.isEmpty ? 0 : (_cursor - 1 + items.length) % items.length),
              },
              child: TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Œuvre, site, onglet…  (Entrée pour ouvrir, Échap pour fermer)',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Ctrl+K', style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
                ),
                onChanged: (v) => setState(() {
                  _query = v;
                  _cursor = 0;
                }),
                onSubmitted: (_) {
                  if (items.isNotEmpty) _run(items[_cursor]);
                },
              ),
            ),
            Divider(height: 1, color: p.border),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Rien ne correspond.', style: TextStyle(color: p.muted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        return ListTile(
                          selected: i == _cursor,
                          selectedTileColor: p.selected,
                          leading: it.coverUrl != null
                              ? SizedBox(width: 30, child: CoverImage(url: it.coverUrl, radius: 5))
                              : Icon(it.icon, color: p.bright),
                          title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12)),
                          onTap: () => _run(it),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
