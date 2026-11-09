import 'dart:async';

import 'package:flutter/material.dart';

import '../core/anime/anilist.dart';
import '../core/anime/crunchyroll.dart';
import '../core/models.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'external_link.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'widgets/crunchyroll_actions.dart';
import 'widgets/motion.dart';

/// Fiche d'un animé : métadonnées AniList, prochain épisode à l'heure près,
/// suivi des épisodes vus et liens vers les plateformes officielles.
/// Pazulu ne lit ni n'extrait aucune vidéo : on regarde chez l'éditeur.
class AnimePage extends StatefulWidget {
  const AnimePage({super.key, required this.work, this.info, this.heroTag});

  final WorkInfo work;
  final AnimeInfo? info;
  final String? heroTag;

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  AnimeInfo? _info;
  Object? _error;
  bool _loading = false;
  bool _expanded = false;
  Timer? _tick;
  bool _requested = false;
  Map<int, DateTime> _airDates = const {};
  bool _allEpisodes = false;

  int? get _id => widget.info?.id ?? AniListClient.idOf(widget.work);

  @override
  void initState() {
    super.initState();
    _info = widget.info;
    // The countdown stays exact without rebuilding every second.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cards carry light data: the full record (links, relations) is always
    // fetched once; cached data is shown meanwhile.
    if (!_requested) {
      _requested = true;
      final cached = _id == null ? null : AppScope.read(context).animeInfos[_id];
      if (_info == null && cached != null) _info = cached;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
        // French release times (hourly cache); rebuilds when loaded.
        if (mounted) AppScope.read(context).loadFrPlanning();
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) {
      setState(() => _error = 'Identifiant AniList introuvable pour cette fiche.');
      return;
    }
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await app.anilist.details(id);
      app.animeInfos[id] = info;
      if (mounted) setState(() => _info = info);
      unawaited(_loadAirDates(info));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = AppScope.of(context);
    final info = _info;
    final entry = app.entry(widget.work.id);
    final title = info?.title ?? widget.work.title;
    final banner = info?.banner ?? info?.cover ?? widget.work.coverUrl;

    return Scaffold(
      backgroundColor: p.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            backgroundColor: p.background,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (entry != null)
                IconButton(
                  tooltip: 'Retirer de la bibliothèque',
                  onPressed: () => app.removeFromLibrary(widget.work.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _Banner(url: banner),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeSlideIn(index: 0, child: _hero(context, info, entry)),
                      if (_loading && info == null)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null && info == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: ErrorState(error: _error!, onRetry: _load),
                        ),
                      if (info != null) ...[
                        const SizedBox(height: 24),
                        _nextEpisode(context, info),
                        const SizedBox(height: 16),
                        _progress(context, info, entry),
                        if (Crunchyroll.isOn(info)) ...[
                          const SizedBox(height: 24),
                          _episodes(context, info, entry),
                        ],
                        const SizedBox(height: 24),
                        _whereToWatch(context, info),
                        if (info.description.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _description(context, info),
                        ],
                        if (info.relations.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _relations(context, info),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, AnimeInfo? info, LibraryEntry? entry) {
    final p = context.pal;
    final t = Theme.of(context).textTheme;
    final app = AppScope.read(context);
    final w = widget.work;
    final cover = CoverImage(url: info?.cover ?? w.coverUrl);
    final facts = <String>[
      if (info?.format != null) _formatLabel(info!.format!),
      if (info?.seasonLabel != null) info!.seasonLabel!,
      if (info?.episodes != null) '${info!.episodes} épisodes'
      else if (info?.airedEpisodes != null) '${info!.airedEpisodes} épisodes diffusés',
      if (info?.duration != null) '${info!.duration} min',
    ];

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          Tag(info?.statusLabel ?? w.publicationStatus ?? 'Animé',
              color: _statusColor(context, info?.status), icon: Icons.circle),
          if (info?.score != null) Tag('${info!.score}%', icon: Icons.star_rounded),
        ]),
        const SizedBox(height: 12),
        Text(info?.title ?? w.title, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: t.headlineLarge?.copyWith(fontSize: 32, height: 1.12)),
        if ((info?.altTitles ?? w.altTitles).isNotEmpty) ...[
          const SizedBox(height: 6),
          Text((info?.altTitles ?? w.altTitles).take(2).join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(facts.join('  ·  '), style: TextStyle(color: p.text.withValues(alpha: 0.85))),
        ],
        if ((info?.studios ?? w.authors).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Studio : ${(info?.studios ?? w.authors).take(2).join(', ')}',
              style: TextStyle(color: p.muted, fontSize: 13)),
        ],
        if ((info?.genres ?? w.tags).isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6,
              children: [for (final g in (info?.genres ?? w.tags).take(8)) Tag(g)]),
        ],
        const SizedBox(height: 18),
        if (info != null && Crunchyroll.isOn(info)) ...[
          Builder(builder: (context) {
            final ep = _nextToWatch(info, entry);
            return CrunchyrollButtons(url: app.crunchyrollEpisodeUrl(info, ep)!, title: info.title,
                hints: Crunchyroll.seasonHints(info),
                episode: ep,
                onEpisodeUrl: ep == null ? null : (u) => app.rememberCrunchyrollEpisode(info, ep, u));
          }),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (info != null && info.streaming.isNotEmpty && !Crunchyroll.isOn(info))
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              onPressed: () => openOfficialLink(context, info.streaming.first.url),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Regarder sur ${info.streaming.first.site}'),
            ),
          if (entry == null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
              onPressed: info == null ? null : () => app.addAnime(info),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter à ma liste'),
            )
          else
            PopupMenuButton<TrackStatus>(
              tooltip: 'Statut de suivi',
              initialValue: entry.status,
              onSelected: (s) => app.updateEntry(entry.work.id, (e) => e.status = s),
              itemBuilder: (_) => [
                for (final s in TrackStatus.values)
                  PopupMenuItem(value: s, child: Text(_watchLabel(s))),
              ],
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(PazuluRadius.card),
                  border: Border.all(color: p.borderStrong),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bookmark_rounded, size: 18, color: p.bright),
                  const SizedBox(width: 8),
                  Text(_watchLabel(entry.status),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, color: p.muted),
                ]),
              ),
            ),
          if (entry != null)
            IconButton.outlined(
              tooltip: entry.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
              onPressed: () => app.updateEntry(entry.work.id, (e) => e.favorite = !e.favorite),
              icon: Icon(entry.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: entry.favorite ? p.accent : null),
            ),
        ]),
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 640;
      final coverBox = Transform.translate(
        offset: const Offset(0, -60),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Ombre « Kiosque » sans flou : pas de recalcul coûteux au défilement.
            boxShadow: [BoxShadow(color: p.ink, offset: const Offset(6, 6))],
          ),
          child: widget.heroTag == null ? cover : Hero(tag: widget.heroTag!, child: cover),
        ),
      );
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 190, child: coverBox),
          const SizedBox(width: 28),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 20), child: details)),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: coverBox),
        Transform.translate(offset: const Offset(0, -40), child: details),
      ]);
    });
  }

  /// Japanese airing date of every aired episode (AniList), for the list.
  Future<void> _loadAirDates(AnimeInfo info) async {
    final from = info.startDate?.subtract(const Duration(days: 7)) ??
        DateTime.now().subtract(const Duration(days: 400));
    try {
      final list = await AppScope.read(context).anilist.schedule([info.id], from, DateTime.now());
      if (mounted) setState(() => _airDates = {for (final a in list) a.episode: a.airingAt});
    } catch (_) {
      // dates are a bonus: the list works without them
    }
  }

  void _openEpisode(AnimeInfo info, int n) {
    final app = AppScope.read(context);
    final url = app.crunchyrollEpisodeUrl(info, n);
    if (url == null) return;
    watchOnCrunchyroll(context, url, title: info.title, episode: n, hints: Crunchyroll.seasonHints(info),
        onCrunchyrollNumber: (k) => app.rememberCrunchyrollNumber(info, n, k),
        onEpisodeUrl: (u) => app.rememberCrunchyrollEpisode(info, n, u));
  }

  /// Episodes like the chapters of a manga: newest first, click = watch
  /// this episode in Pazulu, the check marks it seen.
  Widget _episodes(BuildContext context, AnimeInfo info, LibraryEntry? entry) {
    final p = context.pal;
    final app = AppScope.read(context);
    final aired = info.airedEpisodes ?? info.episodeLinks.fold<int>(0, (m, e) => e.number > m ? e.number : m);
    if (aired <= 0) return const SizedBox.shrink();
    final watched = entry?.episodesWatched ?? 0;
    final crOffset = AppScope.of(context).crNumberOffsets[info.id];
    final titles = {for (final e in info.episodeLinks) if (Crunchyroll.isCrunchyrollUrl(e.url)) e.number: e.title};
    final numbers = [for (var n = aired; n >= 1; n--) n];
    final shown = _allEpisodes ? numbers : numbers.take(24).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Épisodes',
          subtitle: '$aired disponible(s) · clic = regarder dans Pazulu · ✓ = vu',
          padding: EdgeInsets.zero),
      const SizedBox(height: 12),
      for (final n in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PressableBox(
            onTap: () => _openEpisode(info, n),
            color: n <= watched ? p.surface : p.card,
            shadow: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 64,
                  child: Text('ÉP. $n', style: kiosqueDisplay(15,
                      color: n <= watched ? p.muted : p.text)),
                ),
                Expanded(
                  child: Text(
                    _episodeTitle(titles[n], n),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: n <= watched ? p.muted : p.text, fontWeight: FontWeight.w600),
                  ),
                ),
                if ((crOffset ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Crunchyroll continue la numérotation des saisons précédentes',
                      child: Text('E${n + crOffset!} sur Crunchyroll',
                          style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (_airDates[n] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(shortDate(_airDates[n]!),
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.play_arrow_rounded, color: p.accent),
                IconButton(
                  tooltip: n <= watched ? 'Marquer comme non vu' : 'Marquer comme vu (et les précédents)',
                  onPressed: () => app.setEpisodesWatched(info, n <= watched ? n - 1 : n),
                  icon: Icon(n <= watched ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: n <= watched ? p.accent : p.muted),
                ),
              ]),
            ),
          ),
        ),
      if (numbers.length > shown.length || _allEpisodes && numbers.length > 24)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _allEpisodes = !_allEpisodes),
            icon: Icon(_allEpisodes ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(_allEpisodes ? 'Réduire' : 'Voir les ${numbers.length} épisodes'),
          ),
        ),
    ]);
  }

  /// « Episode 8 - Le titre » → « Le titre ».
  static String _episodeTitle(String? raw, int n) {
    if (raw == null || raw.trim().isEmpty) return 'Épisode $n';
    final t = raw.replaceFirst(RegExp(r'^\s*(?:episode|épisode|ep\.?)\s*\d+\s*[-:–]?\s*', caseSensitive: false), '').trim();
    return t.isEmpty ? 'Épisode $n' : t;
  }

  /// Next episode to watch: the one after the last watched, when it has
  /// already aired (otherwise none: the series page is opened).
  int? _nextToWatch(AnimeInfo info, LibraryEntry? entry) {
    final next = (entry?.episodesWatched ?? 0) + 1;
    final aired = info.airedEpisodes;
    if (aired == null || next > aired) return null;
    return next;
  }

  Widget _nextEpisode(BuildContext context, AnimeInfo info) {
    final p = context.pal;
    final next = info.nextAiring;
    final IconData icon;
    final String headline;
    final String detail;
    final fr = AppScope.of(context).frPlanning;
    final onCr = Crunchyroll.isOn(info);
    final frAt = next == null ? null
        : onCr ? Crunchyroll.frenchTime(fr, info, next.airingAt)
        : fr?.releaseFor(info, next.airingAt)?.at;
    if (next != null && frAt != null) {
      icon = Icons.schedule_rounded;
      headline = 'Épisode ${next.episode} · ${countdown(frAt)}';
      detail = '${onCr ? 'Sur Crunchyroll France' : 'En France (VOSTFR)'} : ${shortDate(frAt)} vers '
          '${clockTime(frAt)}. Diffusion au Japon : ${shortDate(next.airingAt)} à ${clockTime(next.airingAt)}.'
          '${fr != null && fr.postponed(info) ? ' Attention : annoncé comme reporté cette semaine.' : ''}';
    } else if (next != null) {
      icon = Icons.schedule_rounded;
      headline = 'Épisode ${next.episode} · ${countdown(next.airingAt)}';
      detail = 'Japon : ${shortDate(next.airingAt)} à ${clockTime(next.airingAt)} (heure française). '
          '${fr == null ? 'Planning France pas encore chargé' : 'Pas encore dans le planning France de la semaine'} : '
          'la sortie française suit en général de peu.';
    } else if (info.status == 'HIATUS') {
      icon = Icons.pause_circle_outline_rounded;
      headline = 'En pause (hiatus)';
      detail = 'AniList indique une interruption de la diffusion. La reprise sera affichée dès qu\'une date est annoncée.';
    } else if (info.status == 'NOT_YET_RELEASED') {
      icon = Icons.event_rounded;
      headline = info.startDate != null
          ? 'Première diffusion le ${shortDate(info.startDate!)}'
          : 'Date de diffusion pas encore annoncée';
      detail = info.seasonLabel != null ? 'Saison prévue : ${info.seasonLabel}.' : 'Aucune date officielle pour le moment.';
    } else if (info.upcomingSequels.isNotEmpty) {
      final s = info.upcomingSequels.first;
      icon = Icons.new_releases_outlined;
      headline = 'Nouvelle saison : ${s.title}';
      detail = s.startDate != null
          ? 'Début prévu le ${shortDate(s.startDate!)}.'
          : (s.season != null || s.seasonYear != null
              ? 'Annoncée pour ${[s.season, s.seasonYear].whereType<Object>().join(' ')}.'
              : 'Annoncée, date encore inconnue.');
    } else {
      icon = Icons.check_circle_outline_rounded;
      headline = info.status == 'FINISHED' ? 'Diffusion terminée' : 'Aucun épisode programmé';
      detail = info.endDate != null ? 'Dernier épisode le ${shortDate(info.endDate!)}.' : 'Aucune diffusion annoncée.';
    }
    return Glass(
      highlight: next != null,
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: p.bright),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(headline, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _progress(BuildContext context, AnimeInfo info, LibraryEntry? entry) {
    final p = context.pal;
    final app = AppScope.read(context);
    final watched = entry?.episodesWatched ?? 0;
    final total = info.episodes;
    final aired = info.airedEpisodes;
    final cap = total ?? aired;
    final behind = aired != null ? aired - watched : null;
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Épisodes vus', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton.outlined(
            tooltip: 'Un épisode de moins',
            onPressed: watched <= 0 ? null : () => app.setEpisodesWatched(info, watched - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 92,
            child: Text(cap == null ? '$watched' : '$watched / $cap',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          IconButton.filled(
            tooltip: 'Épisode suivant vu',
            onPressed: cap != null && watched >= cap ? null : () => app.setEpisodesWatched(info, watched + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: cap == null || cap == 0 ? null : (watched / cap).clamp(0, 1).toDouble(),
            backgroundColor: p.surfaceHigh,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          behind == null
              ? 'Suivez votre avancement épisode par épisode.'
              : behind <= 0
                  ? 'Vous êtes à jour.'
                  : '$behind épisode(s) diffusé(s) à rattraper.',
          style: TextStyle(color: behind != null && behind > 0 ? p.bright : p.muted, fontSize: 13),
        ),
      ]),
    );
  }

  Widget _whereToWatch(BuildContext context, AnimeInfo info) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('Où regarder',
          subtitle: Crunchyroll.isOn(info)
              ? 'Sur Crunchyroll · ton compte et le lecteur officiel, dans ton navigateur'
              : 'Plateformes officielles publiées par AniList · ouverture dans votre navigateur',
          padding: EdgeInsets.zero),
      const SizedBox(height: 12),
      if (info.streaming.isEmpty)
        Text('Aucune plateforme officielle référencée pour le moment.',
            style: TextStyle(color: p.muted))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in info.streaming)
            if (Crunchyroll.isCrunchyrollUrl(s.url))
              // Crunchyroll : lecture dans Pazulu (navigateur intégré).
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => watchOnCrunchyroll(context, s.url, title: info.title),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Crunchyroll · dans Pazulu'),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => openOfficialLink(context, s.url),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(s.language == null ? s.site : '${s.site} · ${s.language}'),
              ),
        ]),
      if (info.siteUrl != null || info.trailerYoutube != null) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 4, children: [
          if (info.trailerYoutube != null)
            TextButton.icon(
              onPressed: () => openOfficialLink(context, 'https://www.youtube.com/watch?v=${info.trailerYoutube}'),
              icon: const Icon(Icons.smart_display_outlined, size: 18),
              label: const Text('Bande-annonce'),
            ),
          if (info.siteUrl != null)
            TextButton.icon(
              onPressed: () => openOfficialLink(context, info.siteUrl!),
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('Fiche AniList'),
            ),
        ]),
      ],
    ]);
  }

  Widget _description(BuildContext context, AnimeInfo info) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Synopsis', padding: EdgeInsets.zero),
      const SizedBox(height: 8),
      AnimatedSize(
        duration: PazuluMotion.of(context, const Duration(milliseconds: 210)),
        alignment: Alignment.topLeft,
        child: Text(info.description, maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(color: p.text.withValues(alpha: 0.85), height: 1.55)),
      ),
      TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
        child: Text(_expanded ? 'Réduire' : 'Lire la suite'),
      ),
    ]);
  }

  Widget _relations(BuildContext context, AnimeInfo info) {
    final p = context.pal;
    const order = ['PREQUEL', 'SEQUEL', 'PARENT', 'SIDE_STORY', 'SPIN_OFF', 'ALTERNATIVE', 'SOURCE', 'ADAPTATION'];
    final rels = [...info.relations]
      ..sort((a, b) {
        int rank(String r) { final i = order.indexOf(r); return i < 0 ? 99 : i; }
        return rank(a.relation).compareTo(rank(b.relation));
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Saisons et œuvres liées', padding: EdgeInsets.zero),
      const SizedBox(height: 12),
      SizedBox(
        height: 236,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: rels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final r = rels[i];
            final isAnime = r.type == 'ANIME';
            return SizedBox(
              width: 120,
              child: InkWell(
                borderRadius: BorderRadius.circular(PazuluRadius.card),
                onTap: !isAnime ? null : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AnimePage(work: WorkInfo(
                    id: 'anilist:${r.id}', title: r.title, coverUrl: r.cover,
                    type: ContentType.anime,
                    links: [SourceLink(sourceId: AniListClient.sourceId, workId: '${r.id}')],
                  )),
                )),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CoverImage(url: r.cover),
                  const SizedBox(height: 6),
                  Text(_relationLabel(r.relation),
                      style: TextStyle(color: p.bright, fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  static String _watchLabel(TrackStatus s) => switch (s) {
        TrackStatus.discover => 'À découvrir',
        TrackStatus.planned => 'À regarder',
        TrackStatus.reading => 'En cours',
        TrackStatus.paused => 'En pause',
        TrackStatus.completed => 'Terminé',
        TrackStatus.dropped => 'Abandonné',
      };

  static String _formatLabel(String f) => switch (f) {
        'TV' => 'Série TV',
        'TV_SHORT' => 'Format court',
        'MOVIE' => 'Film',
        'SPECIAL' => 'Spécial',
        'OVA' => 'OVA',
        'ONA' => 'ONA',
        'MUSIC' => 'Clip',
        _ => f,
      };

  static String _relationLabel(String r) => switch (r) {
        'SEQUEL' => 'SUITE',
        'PREQUEL' => 'AVANT',
        'SIDE_STORY' => 'HISTOIRE PARALLÈLE',
        'SPIN_OFF' => 'SPIN-OFF',
        'ADAPTATION' => 'ADAPTATION',
        'SOURCE' => 'ŒUVRE ORIGINALE',
        'PARENT' => 'SÉRIE PRINCIPALE',
        'ALTERNATIVE' => 'VERSION ALTERNATIVE',
        'SUMMARY' => 'RÉSUMÉ',
        _ => r.replaceAll('_', ' '),
      };

  Color? _statusColor(BuildContext context, String? status) {
    final p = context.pal;
    return switch (status) {
      'RELEASING' => p.success,
      'HIATUS' => p.warning,
      'CANCELLED' => p.danger,
      'NOT_YET_RELEASED' => p.bright,
      _ => null,
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Banner decoded once at screen width (not the full original) and
    // kept in its own layer: the parallax only moves it.
    return RepaintBoundary(child: Stack(fit: StackFit.expand, children: [
      if (url != null)
        Image.network(url!, fit: BoxFit.cover, cacheWidth: 1600, gaplessPlayback: true,
            filterQuality: FilterQuality.low, errorBuilder: (_, __, ___) => const SizedBox())
      else
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            colors: [p.primary.withValues(alpha: 0.4), p.accent.withValues(alpha: 0.2)]))),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [p.background.withValues(alpha: 0.35), p.background],
            stops: const [0.3, 1],
          ),
        ),
      ),
    ]));
  }
}
