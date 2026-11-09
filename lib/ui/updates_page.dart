import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/release_scan.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'format.dart';
import 'home_page.dart';
import 'read_actions.dart';
import 'work_page.dart';
import 'widgets/common.dart';
import 'widgets/motion.dart';

/// Tableau de bord des chapitres, sans changement des flux ni des donnees.
/// Le rendu utilise exclusivement les couleurs de la palette Pazulu active.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    if (diff < 7) return 'Cette semaine';
    return 'Plus tôt';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final groups = <String, List<UpdateItem>>{};
    for (final u in app.updates) {
      groups.putIfAbsent(_dayLabel(u.releasedAt), () => []).add(u);
    }
    var index = 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await app.checkUpdates(forceSiteScan: true);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.xl),
            children: [
              const _UpdatesHero(),
              const SizedBox(height: PazuluSpace.lg),
              const _OverviewMetrics(),
              if (app.lastCheckError != null) ...[
                const SizedBox(height: PazuluSpace.md),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  title: 'Vérification partielle',
                  message: app.lastCheckError!,
                ),
              ],
              if (app.lastListingError != null && app.listingFailures > 0) ...[
                const SizedBox(height: PazuluSpace.sm),
                _Notice(
                  icon: Icons.info_outline_rounded,
                  title: '${app.listingFailures} fiche(s) non vérifiables',
                  message: 'Dernier motif : ${app.lastListingError}. '
                      'Une page inaccessible ne compte jamais comme sortie confirmée.',
                ),
              ],
              const SizedBox(height: PazuluSpace.xl),
              if (app.lastCheckAt != null) ...[
                const _FeedReport(),
                const SizedBox(height: PazuluSpace.xl),
              ] else ...[
                _GettingStarted(onCheck: () => app.checkUpdates(forceSiteScan: true)),
                const SizedBox(height: PazuluSpace.xl),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text('Dernières publications',
                      style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Tag('${app.updates.length}', icon: Icons.notifications_outlined),
                  if (app.unseenUpdates > 0) ...[
                    const SizedBox(width: PazuluSpace.sm),
                    TextButton(
                      onPressed: app.markUpdatesSeen,
                      child: const Text('Tout marquer vu'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: PazuluSpace.md),
              if (app.updates.isEmpty)
                const _QuietEmptyState()
              else
                for (final g in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                        top: PazuluSpace.sm, bottom: PazuluSpace.md),
                    child: Text(
                      g.key.toUpperCase(),
                      style: TextStyle(
                        color: p.bright,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  for (final u in g.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: PazuluSpace.sm),
                      child: FadeSlideIn(
                        index: index++,
                        child: UpdateRow(item: u),
                      ),
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdatesHero extends StatelessWidget {
  const _UpdatesHero();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final lastCheck = app.lastCheckAt == null
        ? 'Pas encore de vérification'
        : 'Dernier contrôle ${relativeTime(app.lastCheckAt)}';
    final cadence = app.settings.autoCheckMinutes == 0
        ? 'Surveillance automatique désactivée'
        : 'Surveillance toutes les ${app.settings.autoCheckMinutes} min';

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 14, color: p.bright),
            const SizedBox(width: PazuluSpace.sm),
            Text('CENTRE DE SUIVI', style: TextStyle(
              color: p.bright,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            )),
          ],
        ),
        const SizedBox(height: PazuluSpace.sm),
        Text('Nouveautés', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: PazuluSpace.xs),
        Text('Retrouve tes chapitres et les vérifications de tes sources.',
          style: TextStyle(color: p.muted, fontSize: 14)),
        const SizedBox(height: PazuluSpace.sm),
        Wrap(
          spacing: PazuluSpace.md,
          runSpacing: PazuluSpace.xs,
          children: [
            _InlineInfo(icon: Icons.schedule_rounded, label: lastCheck),
            _InlineInfo(icon: Icons.sync_rounded, label: cadence),
          ],
        ),
      ],
    );

    final action = GlowButton(
      label: app.checking ? 'Vérification…' : 'Vérifier les sorties',
      icon: app.checking ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
      onPressed: app.checking ? null : () => app.checkUpdates(forceSiteScan: true),
    );

    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 640;
      return narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: PazuluSpace.md), action],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: heading), const SizedBox(width: 20), action],
            );
    });
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: p.muted, size: 14),
      const SizedBox(width: 5),
      Flexible(child: Text(label,
        maxLines: 2, softWrap: true, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.muted, fontSize: 12))),
    ]);
  }
}

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final hasCheck = app.lastCheckAt != null;
    final metrics = [
      ('Œuvres suivies', '${app.entries.where((e) => e.watch).length}',
        Icons.bookmark_added_outlined, 'Dans ta bibliothèque'),
      ('Flux contrôlés', hasCheck ? '${app.verifiedFeeds}' : '—',
        Icons.fact_check_outlined, 'Fiches vraiment analysées'),
      ('Chapitres à lire', hasCheck ? '${app.confirmedUnread}' : '—',
        Icons.menu_book_outlined, 'Dans les flux contrôlés'),
      ('Contrôles en échec', hasCheck ? '${app.failedFeeds}' : '—',
        Icons.report_gmailerrorred_rounded, 'Sources non vérifiables'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 850 ? 4 : (width >= 460 ? 2 : 1);
      final tileWidth = (width - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in metrics)
            SizedBox(
              width: tileWidth,
              child: _MetricTile(
                title: item.$1, value: item.$2,
                icon: item.$3, footnote: item.$4,
              ),
            ),
        ],
      );
    });
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title, required this.value,
    required this.icon, required this.footnote,
  });
  final String title;
  final String value;
  final IconData icon;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(PazuluSpace.md),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.83),
        border: Border.all(color: p.borderStrong),
        borderRadius: BorderRadius.circular(PazuluRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600))),
          Icon(icon, color: p.bright, size: 19),
        ]),
        const SizedBox(height: PazuluSpace.md),
        Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800)),
        const SizedBox(height: PazuluSpace.xs),
        Text(footnote, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Glass(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: p.bright, size: 22),
        const SizedBox(width: PazuluSpace.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: PazuluSpace.xs),
          Text(message, style: TextStyle(color: p.muted, fontSize: 13)),
        ])),
      ]),
    );
  }
}

class _GettingStarted extends StatelessWidget {
  const _GettingStarted({required this.onCheck});
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(PazuluSpace.lg),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ta surveillance est prête', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: PazuluSpace.sm),
      Text('Lance un contrôle pour connaître les chapitres disponibles et les '
          'sources réellement analysées.',
          style: TextStyle(color: context.pal.muted)),
      const SizedBox(height: PazuluSpace.md),
      GhostButton(label: 'Lancer le premier contrôle',
        icon: Icons.play_arrow_rounded, onPressed: onCheck),
    ]),
  );
}

class _FeedReport extends StatelessWidget {
  const _FeedReport();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final works = app.entries.where((e) => e.watch).toList();
    final reports = app.feedChecks;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Disponibilité de tes lectures',
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: PazuluSpace.xs),
      Text('Chaque carte indique les sources vraiment contrôlées et les '
          'chapitres disponibles. Les sites non liés ne sont pas comptés.',
        style: TextStyle(color: p.muted, fontSize: 13)),
      const SizedBox(height: PazuluSpace.md),
      if (works.isEmpty)
        _Notice(icon: Icons.bookmark_add_outlined,
          title: 'Aucune œuvre surveillée',
          message: 'Ajoute une œuvre à ta bibliothèque puis active son suivi.')
      else
        for (final entry in works) ...[
          _WorkFeedCard(
            entry: entry,
            reports: reports.where((r) => r.workId == entry.work.id).toList(),
          ),
          const SizedBox(height: PazuluSpace.md),
        ],
      _Notice(
        icon: Icons.info_outline_rounded,
        title: 'Comment sont calculés ces résultats ?',
        message: 'Une source doit fournir une liste de chapitres utilisable pour '
            'être comptée comme vérifiée. Les sites dynamiques ou bloqués '
            'restent non vérifiables, et les chapitres non lus ne sont pas '
            'nécessairement de nouvelles publications.',
      ),
    ]);
  }
}

class _WorkFeedCard extends StatelessWidget {
  const _WorkFeedCard({required this.entry, required this.reports});
  final LibraryEntry entry;
  final List<FeedCheckResult> reports;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final verified = reports.where((r) => r.confirmed).length;
    final unread = <String>{
      for (final report in reports)
        if (report.confirmed) ...report.unreadKeys,
    }.length;
    final hasExternal = entry.savedSiteLinks.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(PazuluRadius.big),
        border: Border.all(color: p.borderStrong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(PazuluSpace.md),
          child: LayoutBuilder(builder: (context, box) {
            final narrow = box.maxWidth < 540;
            final header = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: 68, child: CoverImage(
                url: entry.work.coverUrl, radius: PazuluRadius.sm)),
              const SizedBox(width: PazuluSpace.md),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.work.title, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: PazuluSpace.sm),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Tag('$verified flux vérifié${verified > 1 ? 's' : ''}',
                      icon: Icons.verified_outlined, color: p.bright),
                    if (unread > 0)
                      Tag('$unread à lire', icon: Icons.bookmark_border_rounded,
                        color: p.accent),
                  ]),
                ],
              )),
            ]);
            final linkButton = TextButton.icon(
              onPressed: () => pushPage(context, WorkPage(
                work: entry.work, heroTag: 'check-${entry.work.id}')),
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('Lier une source'),
            );
            return narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    header, const SizedBox(height: 4), linkButton,
                  ])
                : Row(children: [
                    Expanded(child: header),
                    const SizedBox(width: PazuluSpace.sm),
                    linkButton,
                  ]);
          }),
        ),
        if (reports.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                PazuluSpace.md, 0, PazuluSpace.md, PazuluSpace.md),
            child: Text('Aucun flux contrôlé pour cette œuvre. '
                'Relie sa fiche sur un site compatible pour commencer.',
              style: TextStyle(color: p.muted, fontSize: 13)),
          )
        else ...[
          Divider(height: 1, color: p.borderStrong),
          for (var i = 0; i < reports.length; i++) ...[
            _FeedSourceRow(entry: entry, result: reports[i]),
            if (i < reports.length - 1)
              Divider(height: 1, indent: PazuluSpace.md,
                endIndent: PazuluSpace.md, color: p.border),
          ],
        ],
        if (!hasExternal)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                PazuluSpace.md, PazuluSpace.sm,
                PazuluSpace.md, PazuluSpace.md),
            child: Row(children: [
              Icon(Icons.link_off_rounded, color: p.muted, size: 15),
              const SizedBox(width: 7),
              Expanded(child: Text('Autres sites non liés à cette œuvre',
                style: TextStyle(color: p.muted, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}

/// Des libellés explicites complètent les icônes et couleurs d'état.
String feedCheckStatusLabel(FeedCheckState state) => switch (state) {
  FeedCheckState.checked => 'Contrôlé',
  FeedCheckState.failed => 'Échec du contrôle',
  FeedCheckState.unavailable => 'Indisponible',
  FeedCheckState.notConnected => 'Non lié',
  FeedCheckState.rateLimited => 'Accès limité',
};

class _FeedSourceRow extends StatelessWidget {
  const _FeedSourceRow({required this.entry, required this.result});
  final LibraryEntry entry;
  final FeedCheckResult result;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final checked = result.confirmed;
    final stateColor = checked ? p.bright : Theme.of(context).colorScheme.error;
    final details = checked
        ? '${result.chapterCount} chapitres visibles'
          '${result.latestChapter == null ? '' : '  ·  dernier ch. ${result.latestChapter}'}'
        : result.detail.isNotEmpty ? result.detail : feedCheckStatusLabel(result.state);
    final canRead = checked && result.unreadCount > 0;

    void openChapter() {
      // Reprendre la derniere progression canonique, jamais une page web
      // automatiquement : les sources FR/EN partagent la meme chronologie.
      resumeInPazulu(context, entry.work,
        chapterHint: result.nextUnread,
        siteId: result.sourceId,
        chapterUrl: result.nextUrl,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PazuluSpace.md, vertical: PazuluSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PazuluRadius.sm),
          ),
          child: Icon(checked ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded, color: stateColor, size: 20),
        ),
        const SizedBox(width: PazuluSpace.sm),
        LangBadge(result.language),
        const SizedBox(width: PazuluSpace.md),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: PazuluSpace.sm, runSpacing: PazuluSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(result.sourceName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(feedCheckStatusLabel(result.state),
                  style: TextStyle(color: checked ? p.bright : stateColor,
                    fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            const SizedBox(height: PazuluSpace.xs),
            Text(details, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12)),
            if (canRead) ...[
              const SizedBox(height: PazuluSpace.sm),
              Wrap(spacing: PazuluSpace.md, runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${result.unreadCount} à lire', style: TextStyle(
                  color: p.bright, fontSize: 12, fontWeight: FontWeight.w700)),
                TextButton.icon(
                  onPressed: openChapter,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('Reprendre dans Pazulu'),
                ),
              ]),
            ],
          ],
        )),
      ]),
    );
  }
}

class _QuietEmptyState extends StatelessWidget {
  const _QuietEmptyState();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Glass(
      padding: const EdgeInsets.all(PazuluSpace.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: p.bright.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(PazuluRadius.card),
          ),
          child: Icon(Icons.notifications_none_rounded, color: p.bright, size: 26),
        ),
        const SizedBox(width: PazuluSpace.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aucune nouvelle publication détectée',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700)),
          const SizedBox(height: PazuluSpace.xs),
          Text('Les chapitres déjà disponibles sont affichés plus haut. '
              'Une absence de notification ne signifie pas que tout est lu.',
            style: TextStyle(color: p.muted, fontSize: 13)),
        ])),
      ]),
    );
  }
}
