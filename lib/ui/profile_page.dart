import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'settings_page.dart';
import 'widgets/common.dart';
import 'work_page.dart';

IconData achievementIcon(String key) => switch (key) {
      'book' => Icons.menu_book_rounded,
      'tv' => Icons.live_tv_rounded,
      'star' => Icons.star_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'heart' => Icons.favorite_rounded,
      'globe' => Icons.public_rounded,
      'bolt' => Icons.bolt_rounded,
      'shelf' => Icons.collections_bookmark_rounded,
      'calendar' => Icons.calendar_month_rounded,
      'crown' => Icons.workspace_premium_rounded,
      'moon' => Icons.nightlight_round,
      'clock' => Icons.schedule_rounded,
      'sparkle' => Icons.auto_awesome_rounded,
      'language' => Icons.translate_rounded,
      'pen' => Icons.edit_note_rounded,
      _ => Icons.military_tech_rounded,
    };

/// Profil : niveau, expérience, statistiques de l'année et succès.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const _months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final s = app.stats;
    final level = Level.of(s.xp);
    final unlocked = app.activity.unlocked;
    final hours = (s.yearMinutes / 60).round();
    final done = Achievements.all.where((a) => unlocked.containsKey(a.id)).length;

    Widget stat(String value, String label, IconData icon) => Expanded(
          child: Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: p.bright),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()])),
              Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        );

    final maxMonth = s.months.fold<int>(1, (m, v) => v > m ? v : m);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(PazuluSpace.lg),
              children: [
                const PageTitle('Profil', kicker: 'Statistiques, succès, sauvegarde', size: 40),
                const SizedBox(height: PazuluSpace.md),
                // Level card
                Glass(
                  highlight: true,
                  child: Row(children: [
                    SizedBox(
                      width: 96, height: 96,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(child: CircularProgressIndicator(
                          value: level.progress, strokeWidth: 7,
                          backgroundColor: p.surfaceHigh, color: p.bright)),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('NIV.', style: TextStyle(color: p.muted, fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 1)),
                          Text('${level.number}', style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w900)),
                        ]),
                      ]),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(level.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('${s.xp} XP · encore ${level.next - s.xp} XP pour le niveau ${level.number + 1}',
                          style: TextStyle(color: p.muted)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Tag('$done/${Achievements.all.length} succès', icon: Icons.emoji_events_rounded,
                            color: p.warning),
                        if (s.currentStreak > 0)
                          Tag('Série de ${s.currentStreak} j', icon: Icons.local_fire_department_rounded,
                              color: p.danger),
                        Tag('Record ${s.bestStreak} j d\'affilée', icon: Icons.timeline_rounded),
                      ]),
                    ])),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('Chapitre lu : 10 XP · épisode vu : 30 XP · série terminée : 150 XP · favori : 5 XP',
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SectionHeader('Depuis le début', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
                Row(children: [
                  stat('${s.chapters}', 'chapitres lus', Icons.menu_book_rounded),
                  const SizedBox(width: 8),
                  stat('${s.episodes}', 'épisodes vus', Icons.live_tv_rounded),
                  const SizedBox(width: 8),
                  stat('${s.completed}', 'séries terminées', Icons.flag_rounded),
                  const SizedBox(width: 8),
                  stat('${s.library}', 'dans ma liste', Icons.collections_bookmark_rounded),
                ]),
                const SectionHeader('En ce moment', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
                Row(children: [
                  stat('${s.weekChapters}', '7 derniers jours', Icons.today_rounded),
                  const SizedBox(width: 8),
                  stat('${s.monthChapters}', 'ce mois-ci', Icons.date_range_rounded),
                  const SizedBox(width: 8),
                  stat('${(s.totalMinutes / 60).round()} h', 'de lecture estimée (au total)', Icons.hourglass_bottom_rounded),
                  const SizedBox(width: 8),
                  stat(s.activeDays == 0 ? '0' : (s.chapters / (s.activeDays < 1 ? 1 : s.activeDays)).toStringAsFixed(1),
                      'chapitres par jour actif', Icons.speed_rounded),
                ]),
                const SizedBox(height: 8),
                Glass(
                  child: Row(children: [
                    Icon(Icons.shield_outlined, color: p.bright),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Sauvegarde de la bibliothèque : progression, favoris, '
                        'historique et réglages dans un fichier .pazulu.',
                        style: TextStyle(color: p.muted, fontSize: 13))),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => SettingsPage.exportLibrary(context, app),
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Exporter'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => SettingsPage.importLibrary(context, app),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Importer'),
                    ),
                  ]),
                ),
                SectionHeader('Mon année ${s.year}', padding: const EdgeInsets.fromLTRB(0, 24, 0, 8)),
                Row(children: [
                  stat('${s.yearChapters}', 'chapitres', Icons.menu_book_rounded),
                  const SizedBox(width: 8),
                  stat('${s.yearEpisodes}', 'épisodes', Icons.live_tv_rounded),
                  const SizedBox(width: 8),
                  stat('$hours h', 'de lecture et d\'animés', Icons.schedule_rounded),
                  const SizedBox(width: 8),
                  stat('${s.activeDays}', 'jours actifs', Icons.calendar_month_rounded),
                ]),
                const SizedBox(height: 8),
                Glass(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Activité par mois', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (var m = 0; m < 12; m++)
                          Expanded(child: Tooltip(
                            message: '${s.months[m]} chapitres et épisodes',
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                height: 4 + 90 * s.months[m] / maxMonth,
                                decoration: BoxDecoration(
                                  color: m == now.month - 1 ? p.bright : p.primary.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_months[m], style: TextStyle(color: p.muted, fontSize: 11)),
                            ]),
                          )),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text('Le journal compte à partir de la version 2.3 ; les totaux « depuis le début » '
                        'incluent toute votre bibliothèque.',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ),
                if (s.topGenres.isNotEmpty || s.topWork != null) ...[
                  const SizedBox(height: 8),
                  Glass(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (s.topWork != null) ...[
                        const Text('Œuvre la plus suivie', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => pushPage(context, WorkPage(work: s.topWork!.work,
                              heroTag: 'profile-${s.topWork!.work.id}')),
                          child: Row(children: [
                            SizedBox(width: 44, child: CoverImage(url: s.topWork!.work.coverUrl, radius: 6)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(s.topWork!.work.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                            Text('${s.topWork!.progress.readKeys.length + s.topWork!.episodesWatched}',
                                style: TextStyle(color: p.bright, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (s.topGenres.isNotEmpty) ...[
                        const Text('Genres préférés', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final g in s.topGenres) Tag(g.key),
                        ]),
                      ],
                    ]),
                  ),
                ],
                SectionHeader('Succès · $done/${Achievements.all.length}',
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 8)),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth > 760 ? 3 : (c.maxWidth > 480 ? 2 : 1);
                  final w = (c.maxWidth - 8 * (cols - 1)) / cols;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in [
                      ...Achievements.all.where((a) => unlocked.containsKey(a.id)),
                      ...(Achievements.all.where((a) => !unlocked.containsKey(a.id)).toList()
                        ..sort((x, y) => y.progress(s).compareTo(x.progress(s)))),
                    ])
                      SizedBox(width: w, child: _AchievementTile(a, stats: s,
                          unlockedAt: DateTime.tryParse(unlocked[a.id] ?? ''))),
                  ]);
                }),
                const SizedBox(height: PazuluSpace.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.a, {required this.stats, this.unlockedAt});
  final Achievement a;
  final ReaderStats stats;
  final DateTime? unlockedAt;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final done = unlockedAt != null;
    final value = a.value(stats);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done ? p.selected : p.card,
        borderRadius: BorderRadius.circular(PazuluRadius.card),
        border: Border.all(color: done ? p.warning.withValues(alpha: 0.5) : p.border),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? p.warning.withValues(alpha: 0.18) : p.surfaceHigh,
          ),
          child: Icon(achievementIcon(a.icon), color: done ? p.warning : p.muted),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title, style: TextStyle(fontWeight: FontWeight.w700,
              color: done ? p.text : p.text.withValues(alpha: 0.8))),
          Text(a.description, style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 6),
          if (done)
            Text('Débloqué le ${unlockedAt!.day.toString().padLeft(2, '0')}/'
                '${unlockedAt!.month.toString().padLeft(2, '0')}/${unlockedAt!.year}',
                style: TextStyle(color: p.warning, fontSize: 11, fontWeight: FontWeight.w600))
          else
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: a.progress(stats), minHeight: 4,
                    backgroundColor: p.surfaceHigh),
              )),
              const SizedBox(width: 8),
              Text('${value > a.target ? a.target : value}/${a.target}',
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
        ])),
      ]),
    );
  }
}
