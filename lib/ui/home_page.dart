import 'read_actions.dart';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'widgets/entry_actions.dart';
import 'widgets/motion.dart';
import 'work_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Bonne nuit';
    if (h < 18) return 'Bonjour';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final resume = app.continueReading();
    final updates = app.updates.take(10).toList();
    final unseen = app.unseenUpdates;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageTitle(_greeting(),
                    kicker: unseen > 0
                        ? '$unseen nouveau${unseen > 1 ? 'x' : ''} chapitre${unseen > 1 ? 's' : ''} depuis votre dernière visite'
                        : 'Votre bibliothèque de lecture, au même endroit',
                    size: 40),
              ],
            ),
          ),
          _SearchShortcut(onTap: () => onNavigate(2)),
        ],
      ),
    );

    final hero = Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 0),
      child: FadeSlideIn(
        index: 0,
        child: resume.isEmpty ? _WelcomeHero(onDiscover: () => onNavigate(2)) : _ResumeHero(entry: resume.first),
      ),
    );

    final shelf = resume.length <= 1
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                'Continuer',
                subtitle: '${resume.length} œuvres en cours · clic droit ou « ⋯ » pour retirer',
                trailing: TextButton(onPressed: () => onNavigate(1), child: const Text('Tout voir')),
              ),
              SizedBox(
                height: 296,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
                  itemCount: resume.length - 1,
                  separatorBuilder: (_, __) => const SizedBox(width: PazuluSpace.md),
                  itemBuilder: (context, i) {
                    final e = resume[i + 1];
                    return SizedBox(
                      width: 150,
                      child: FadeSlideIn(
                        index: i + 1,
                        child: EntryContextMenu(entry: e, child: WorkCard(
                          work: e.work,
                          heroTag: 'home-${e.work.id}',
                          subtitle: progressLabel(e),
                          progress: progressOf(e),
                          badge: app.unreadCount(e) > 0 ? '+${app.unreadCount(e)}' : null,
                          corner: EntryMenuButton(entry: e),
                          onTap: () => pushPage(
                            context,
                            WorkPage(work: e.work, heroTag: 'home-${e.work.id}', autoResume: true),
                          ),
                        )),
                      ),
                    );
                  },
                ),
              ),
            ],
          );

    final updatesPanel = _UpdatesPanel(updates: updates, onSeeAll: () => onNavigate(3));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 1100;
            final mainColumn = RefreshIndicator(
              onRefresh: app.checkUpdates,
              child: ListView(
                padding: const EdgeInsets.only(bottom: PazuluSpace.xl),
                children: [
                  header,
                  if (app.loadWarning != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.md, PazuluSpace.lg, 0),
                      child: Glass(child: Text(app.loadWarning!)),
                    ),
                  hero,
                  shelf,
                  if (!wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 0),
                      child: updatesPanel,
                    ),
                ],
              ),
            );
            if (!wide) return mainColumn;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: mainColumn),
                Container(
                  width: 340,
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(left: BorderSide(color: p.ink, width: 2.5)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(PazuluSpace.lg),
                    children: [updatesPanel],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchShortcut extends StatelessWidget {
  const _SearchShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PressableBox(
      onTap: onTap,
      shadow: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 20, color: p.text),
            const SizedBox(width: 10),
            Text('RECHERCHER UNE ŒUVRE',
                style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(PazuluSpace.xl),
      decoration: kiosqueBox(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Sticker('Bienvenue'),
          const SizedBox(height: PazuluSpace.md),
          Text('COMMENCEZ VOTRE BIBLIOTHÈQUE', style: kiosqueDisplay(36, color: p.text)),
          const SizedBox(height: PazuluSpace.sm),
          Text(
            'Cherchez un manga, un manhwa ou un manhua, ajoutez-le, et Pazulu suit vos chapitres et les nouvelles sorties.',
            style: TextStyle(color: p.text.withValues(alpha: 0.8), fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: PazuluSpace.lg),
          GlowButton(label: 'Découvrir des œuvres', icon: Icons.explore_rounded, onPressed: onDiscover, big: true),
        ],
      ),
    );
  }
}

class _ResumeHero extends StatelessWidget {
  const _ResumeHero({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final w = entry.work;
    final progress = progressOf(entry);
    final heroTag = 'hero-${w.id}';
    void open({bool resume = true}) =>
        pushPage(context, WorkPage(work: w, heroTag: heroTag, autoResume: resume));

    return Container(
      height: 340,
      clipBehavior: Clip.hardEdge,
      decoration: kiosqueBox(p),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                SizedBox(
                  width: 226,
                  child: Stack(fit: StackFit.expand, children: [
                    // Same loader as everywhere (Referer, retry): many sites
                    // refuse a cover without it.
                    Hero(tag: heroTag, child: CoverImage(url: w.coverUrl, ratio: 226 / 335)),
                    const Positioned(top: 12, left: 10, child: Sticker('Reprendre', size: 13)),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(PazuluSpace.lg),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Wrap(spacing: 8, children: [Tag(w.type.label), if (w.languages.isNotEmpty) Tag(w.languages.first)]),
                      const SizedBox(height: PazuluSpace.md),
                      Text(
                        w.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: kiosqueDisplay(40, color: p.text).copyWith(height: 0.98),
                      ),
                      const SizedBox(height: PazuluSpace.sm),
                      Text(progressLabel(entry).toUpperCase(),
                          style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      if (progress != null) ...[
                        const SizedBox(height: PazuluSpace.md),
                        _AnimatedBar(value: progress),
                      ],
                      const SizedBox(height: PazuluSpace.lg),
                      Wrap(
                        spacing: PazuluSpace.md,
                        runSpacing: PazuluSpace.sm,
                        children: [
                          GlowButton(label: 'Reprendre', icon: Icons.play_arrow_rounded, onPressed: open, big: true),
                          GhostButton(label: 'Fiche', icon: Icons.info_outline, onPressed: () => open(resume: false)),
                          GhostButton(label: 'Retirer', icon: Icons.visibility_off_outlined,
                              onPressed: () => hideFromReading(context, entry)),
                          Builder(builder: (context) => IconButton(
                              tooltip: 'Autres actions',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onPressed: () {
                                final box = context.findRenderObject() as RenderBox?;
                                final at = box == null ? Offset.zero
                                    : box.localToGlobal(box.size.bottomLeft(Offset.zero));
                                showEntryMenu(context, entry, at);
                              })),
                        ],
                      ),
                    ],
                  ),
                  ),
                ),
              ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: PazuluMotion.of(context, const Duration(milliseconds: 900)),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => InkBar(value: v.clamp(0.02, 1.0)),
      ),
    );
  }
}

class _UpdatesPanel extends StatelessWidget {
  const _UpdatesPanel({required this.updates, required this.onSeeAll});

  final List<UpdateItem> updates;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Dernières sorties', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (app.checking)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                tooltip: 'Vérifier les sorties',
                onPressed: app.checkUpdates,
                icon: Icon(Icons.refresh_rounded, color: p.bright),
              ),
          ],
        ),
        const SizedBox(height: PazuluSpace.sm),
        if (updates.isEmpty)
          Glass(
            child: Text(
              app.entries.isEmpty
                  ? 'Ajoutez des œuvres pour suivre leurs sorties.'
                  : 'Aucune nouvelle sortie pour l\'instant. Pazulu vérifie à chaque ouverture.',
              style: TextStyle(color: p.muted),
            ),
          )
        else ...[
          // One line per work and language: « Ch. 226 → 229 », not four rows.
          for (final (i, g) in _grouped(updates).indexed.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: PazuluSpace.sm),
              child: FadeSlideIn(index: i, child: _GroupedUpdateRow(items: g)),
            ),
          Wrap(spacing: 4, children: [
            if (updates.any((u) => !u.seen))
              TextButton.icon(
                onPressed: () => app.markUpdatesSeen(),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Tout marquer comme vu'),
              ),
            TextButton(onPressed: onSeeAll, child: const Text('Voir le planning')),
          ]),
        ],
      ],
    );
  }
}

List<List<UpdateItem>> _grouped(List<UpdateItem> updates) {
  final byKey = <String, List<UpdateItem>>{};
  for (final u in updates) {
    byKey.putIfAbsent('${u.workId}|${u.lang}', () => []).add(u);
  }
  final groups = byKey.values.toList()
    ..sort((a, b) => b.map((u) => u.releasedAt).reduce((x, y) => x.isAfter(y) ? x : y)
        .compareTo(a.map((u) => u.releasedAt).reduce((x, y) => x.isAfter(y) ? x : y)));
  return groups;
}

/// A work's new chapters in one language, on a single clear line.
class _GroupedUpdateRow extends StatelessWidget {
  const _GroupedUpdateRow({required this.items});

  final List<UpdateItem> items;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.pal;
    final sorted = [...items]..sort((a, b) =>
        (a.key.number ?? 0).compareTo(b.key.number ?? 0));
    final first = sorted.first;
    final last = sorted.last;
    final latest = items.map((u) => u.releasedAt).reduce((x, y) => x.isAfter(y) ? x : y);
    final unseen = items.any((u) => !u.seen);
    final entry = app.entry(first.workId);
    final range = sorted.length == 1
        ? first.key.label
        : '${first.key.label} → ${last.key.id} (${sorted.length} chapitres)';
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(PazuluRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(PazuluRadius.card),
        onTap: entry == null
            ? null
            : () {
                app.markUpdatesSeen(workId: first.workId);
                resumeInPazulu(context, entry.work, chapterHint: first.keyId,
                    siteId: first.siteId, chapterUrl: first.chapterUrl);
              },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PazuluRadius.card),
            border: Border.all(color: unseen ? p.bright.withValues(alpha: 0.45) : p.border),
          ),
          child: Row(children: [
            SizedBox(width: 44, child: CoverImage(url: first.coverUrl ?? entry?.work.coverUrl, radius: 8)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(first.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 4),
              Row(children: [
                LangBadge(first.lang),
                const SizedBox(width: 8),
                Expanded(child: Text(range, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.bright, fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
              const SizedBox(height: 2),
              Text(releaseLine(latest), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ])),
            if (unseen)
              Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(color: p.bright, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }
}

/// Ligne d'une nouvelle sortie (accueil et onglet Nouveautés).
class UpdateRow extends StatefulWidget {
  const UpdateRow({super.key, required this.item});

  final UpdateItem item;

  @override
  State<UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<UpdateRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.pal;
    final item = widget.item;
    final entry = app.entry(item.workId);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: PazuluMotion.of(context, PazuluMotion.hover),
        transform: Matrix4.translationValues(_hover ? -2 : 0, _hover ? -2 : 0, 0),
        decoration: kiosqueBox(p, color: _hover ? p.accent.withValues(alpha: p.dark ? 0.18 : 0.4) : p.surface,
            shadow: _hover ? 4 : 2, width: 2),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(PazuluRadius.card),
            onTap: entry == null
                ? null
                : () {
                    app.markUpdatesSeen(workId: item.workId);
                    resumeInPazulu(context, entry.work,
                      chapterHint: item.keyId, siteId: item.siteId,
                      chapterUrl: item.chapterUrl);

                  },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(width: 44, child: CoverImage(url: item.coverUrl, radius: 8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            LangBadge(item.lang),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${item.key.label} · ${relativeTime(item.releasedAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!item.seen)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: p.accent,
                        border: Border.all(color: p.ink, width: 1.5),
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
