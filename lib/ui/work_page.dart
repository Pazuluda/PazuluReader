import 'dart:ui' as ui;


import 'package:flutter/material.dart';

import '../core/chapter_key.dart';
import '../core/chapters.dart';
import '../core/catalogue_audit.dart';
import '../core/models.dart';
import '../core/work_status.dart';
import '../design/theme.dart';
import 'anime_page.dart';
import 'app_scope.dart';
import 'format.dart';
import 'reader_page.dart';
import 'native_source_link_page.dart';
import 'read_actions.dart';
import 'source_browser_page.dart';
import 'widgets/common.dart';
import 'widgets/entry_actions.dart';
import 'widgets/motion.dart';

enum _ChapterFilter { all, en, fr, unread }

/// Fiche d'une œuvre : métadonnées, langues disponibles, suivi, et liste
/// des chapitres avec leurs lecteurs (Lecteur 1, Lecteur 2…).
class WorkPage extends StatefulWidget {
  const WorkPage({super.key, required this.work, required this.heroTag, this.autoResume = false});

  final WorkInfo work;
  final String heroTag;

  /// Ouvre directement le lecteur à la position enregistrée.
  final bool autoResume;

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  Future<List<ChapterGroup>>? _future;
  bool _newestFirst = true;

  /// Reading language chosen on this page (null = automatic / saved).
  String? _langChoice;
  bool _expanded = false;
  bool _genresExpanded = false;
  bool _auditExpanded = false;

  /// « Disponible » shows only the FR / EN counts until « Détails ».
  bool _availabilityExpanded = false;
  bool _resumed = false;
  bool _locatingReaders = false;
  int _seenRevision = -1;
  final Set<String> _unavailableExternalLinks = <String>{};
  _ChapterFilter _filter = _ChapterFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.work.type == ContentType.anime) return;
    if (_seenRevision < 0) {
      _seenRevision = AppScope.read(context).readerRevision(widget.work.id);
    }
    _future ??= _load();
  }

  Future<List<ChapterGroup>> _load({bool refresh = false}) async {
    final groups = await AppScope.read(context).chaptersFor(widget.work, refresh: refresh);
    if (widget.autoResume && !_resumed && mounted) {
      _resumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resume(groups);
      });
    }
    return groups;
  }

  void _refresh() {
    AppScope.read(context).resumePausedSources();
    setState(() => _future = _load(refresh: true));
  }

  Future<void> _toggleDownload(ChapterGroup g, SourceChapter best) async {
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = g.variants.map((v) => app.downloadOf(v.chapterId)).whereType<Object>().isNotEmpty;
    if (saved) {
      for (final v in g.variants) {
        if (app.downloadOf(v.chapterId) != null) await app.deleteDownload(v.chapterId);
      }
      messenger.showSnackBar(SnackBar(content: Text('${g.key.longLabel} retiré du hors ligne')));
      return;
    }
    try {
      await app.downloadChapter(widget.work, best);
      messenger.showSnackBar(SnackBar(content: Text('${g.key.longLabel} disponible hors ligne')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Téléchargement impossible : $e')));
    }
  }

  Future<void> _searchOtherReaders() async {
    if (_locatingReaders) return;
    setState(() => _locatingReaders = true);
    try {
      final app = AppScope.read(context);
      final report = await app.locateNativeReaders(widget.work, showProgress: true);
      if (!mounted) return;
      _refresh();
      final message = report.found > 0
          ? '${report.found} édition(s) lisible(s) trouvée(s) dans Pazulu.'
          : 'Aucune édition supplémentaire confirmée ('
            '${report.checked} sources interrogées, '
            '${report.unavailable} injoignables). '
            'Tu peux associer manuellement une édition.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recherche de sources impossible : $e')));
    } finally { if (mounted) setState(() => _locatingReaders = false); }
  }

  Future<void> _chooseNativeSource() async {
    final chosen = await pushPage(context, NativeSourceLinkPage(work: widget.work));
    if (chosen == true && mounted) _refresh();
  }

  /// External metadata is not a chapter image. Never call a URL-only
  /// chapter a native reader, and never mark it as read on open.
  Future<void> _openExternalChapter(
    SourceChapter selected, ChapterGroup group,
    List<ChapterGroup> groups, int index,
  ) async {
    final candidates = rankVariants(
      group.variants.where((c) => !c.isExternal).toList(),
      langs: AppScope.read(context).settings.comicLangs,
    );
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chapitre ${group.key.label} : lien externe'),
        content: SizedBox(
          width: 420,
          child: Text(
            'Ce lien vers ${selected.group} est reference dans le catalogue, '
            'mais ne fournit pas les images au lecteur Pazulu. Il peut etre '
            'payant, expire ou indisponible (404).\n\n'
            '${candidates.isNotEmpty ? 'Une version native est disponible dans Pazulu.' : 'Aucune autre version native n est encore referencee pour ce chapitre.'}'
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'bad'),
            child: const Text('Lien indisponible')),
          if (candidates.isEmpty)
            FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'search'),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('Chercher sur tous les sites')),
          if (candidates.isNotEmpty)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'native'),
              child: const Text('Lire dans Pazulu')),
          if (selected.externalUrl != null)
            OutlinedButton(onPressed: () => Navigator.pop(ctx, 'official'),
              child: const Text('Consulter la source')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'search') {
      await _searchOtherReaders();
      return;
    }
    if (choice == 'bad') {
      setState(() => _unavailableExternalLinks.add(selected.chapterId));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lien signale comme inaccessible pour cette session. '
          'Utilise une autre version si elle existe.'),
      ));
    } else if (choice == 'native' && candidates.isNotEmpty) {
      await _open(groups, index, variant: candidates.first);
    } else if (choice == 'official' && selected.externalUrl != null) {
      final uri = Uri.tryParse(selected.externalUrl!);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adresse de lecture non securisee ou invalide.'),
        ));
        return;
      }
      await pushPage(context, SourceBrowserPage(
        title: '${widget.work.title} · Chapitre ${group.key.label}',
        url: selected.externalUrl!,
      ));
    }
  }

  void _resume(List<ChapterGroup> groups) {
    if (groups.isEmpty) return;
    // Ne pas choisir automatiquement un simple lien officiel : notre
    // lecteur maison est prioritaire, quelle que soit la source.
    resumeInPazulu(context, widget.work);
  }

  /// First unread chapter after the last one read (null when it is the
  /// one « Reprendre » already opens, or nothing is unread).
  int? _nextUnread(List<ChapterGroup> groups, LibraryEntry? entry) {
    if (entry == null || groups.isEmpty) return null;
    final read = entry.progress.readKeys;
    if (read.isEmpty) return null;
    var lastRead = -1;
    for (var i = 0; i < groups.length; i++) {
      if (read.contains(groups[i].key.id)) lastRead = i;
    }
    for (var i = lastRead + 1; i < groups.length; i++) {
      if (read.contains(groups[i].key.id)) continue;
      if (groups[i].key.id == entry.progress.lastKey) return null;
      final app = AppScope.read(context);
      final unconfirmed = groups[i].variants.isNotEmpty && groups[i].variants.every((v) =>
          app.isAheadUnconfirmed(widget.work.id, v.lang, groups[i].key.id));
      return unconfirmed ? null : i;
    }
    return null;
  }

  /// « 150 » → index of chapter 150 (or the nearest one after it).
  int? _findChapter(List<ChapterGroup> groups, String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final exact = groups.indexWhere((g) => g.key.id == text);
    if (exact >= 0) return exact;
    final n = double.tryParse(text);
    if (n == null) return null;
    final same = groups.indexWhere((g) => g.key.number == n);
    if (same >= 0) return same;
    final after = groups.indexWhere((g) => (g.key.number ?? -1) > n);
    return after >= 0 ? after : null;
  }

  Future<String?> _askChapter(String title, String action) async {
    // Not disposed: the dialog still uses it while it closes.
    final controller = TextEditingController();
    return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Numéro du chapitre', hintText: 'ex. 150'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(action)),
          ],
        ),
      );
  }

  Future<void> _jumpTo(List<ChapterGroup> groups) async {
    final raw = await _askChapter('Aller au chapitre', 'Lire');
    if (raw == null || !mounted) return;
    final i = _findChapter(groups, raw);
    if (i == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chapitre « $raw » introuvable.')));
      return;
    }
    await _open(groups, i);
  }

  Future<void> _markUpTo(List<ChapterGroup> groups) async {
    final raw = await _askChapter('Marquer comme lus jusqu\'au chapitre…', 'Marquer');
    if (raw == null || !mounted) return;
    final i = _findChapter(groups, raw);
    if (i == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chapitre « $raw » introuvable.')));
      return;
    }
    AppScope.read(context).setRead(widget.work, groups.take(i + 1).map((g) => g.key), true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${i + 1} chapitres marqués comme lus (jusqu\'au ${groups[i].key.label})')));
  }

  Future<void> _open(List<ChapterGroup> groups, int index, {int page = 0, SourceChapter? variant}) async {
    await pushPage(
      context,
      ReaderPage(
        work: widget.work,
        groups: groups,
        initialIndex: index,
        initialPage: page,
        initialVariant: variant,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Anime: episodes and official platforms, no chapter engine.
    if (widget.work.type == ContentType.anime) {
      return AnimePage(work: widget.work, heroTag: widget.heroTag);
    }
    final app = AppScope.of(context);
    final p = context.pal;
    final entry = app.entry(widget.work.id);
    // New readers were attached in background (all-sites lookup): reload.
    final revision = app.readerRevision(widget.work.id);
    if (revision != _seenRevision) {
      _seenRevision = revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The list in memory is already the new one (or is reloaded if the
        // sources changed): no second network round.
        if (mounted) setState(() => _future = _load());
      });
    }
    return Scaffold(
      // Search progress is shown in the « Disponible » panel (the floating
      // banner covered the chapter list).
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: p.background)),
          if (widget.work.coverUrl != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 460,
              child: RepaintBoundary(child: ExcludeSemantics(
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                  ).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: Opacity(
                    opacity: 0.22,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                      child: Image.network(
                        widget.work.coverUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      ),
                    ),
                  ),
                ),
              )),
            ),
          const Positioned.fill(child: AmbientGlow()),
          FutureBuilder<List<ChapterGroup>>(
            future: _future,
            builder: (context, snap) {
              final groups = snap.data ?? const <ChapterGroup>[];
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: p.background.withValues(alpha: 0.85),
                      title: Text(widget.work.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      actions: [
                        if (entry != null)
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'remove') {
                                final current = app.entry(widget.work.id);
                                if (current != null) removeWithUndo(context, current);
                              } else if (v == 'watch') {
                                app.updateEntry(widget.work.id, (e) => e.watch = !e.watch);
                              } else if (v == 'refresh') {
                                _refresh();
                              } else if (v == 'import') {
                                importCbzForWork(context, widget.work).then((count) {
                                  if (count > 0 && mounted) _refresh();
                                });
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'refresh', child: Text('Actualiser les chapitres')),
                              PopupMenuItem(
                                value: 'watch',
                                child: Text(entry.watch ? 'Ne plus surveiller les sorties' : 'Surveiller les sorties'),
                              ),
                              const PopupMenuItem(value: 'import', child: Text('Importer un CBZ (facultatif)')),
                              const PopupMenuItem(value: 'remove', child: Text('Retirer de la bibliothèque')),
                            ],
                          ),
                      ],
                    ),
                    SliverToBoxAdapter(child: _header(context, entry, groups)),
                    SliverToBoxAdapter(child: _SavedSourcesSection(work: widget.work)),
                    SliverToBoxAdapter(child: _chapterToolbar(context, groups)),
                    ..._chapterSlivers(context, snap, groups, entry),
                    const SliverToBoxAdapter(child: SizedBox(height: PazuluSpace.xxl)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // En-tête
  // -------------------------------------------------------------------------

  /// Fiche compacte. Les actions ne sont jamais contraintes dans la colonne
  /// de la couverture ; un long libellé ne peut plus déborder dans le résumé.
  Widget _header(BuildContext context, LibraryEntry? entry, List<ChapterGroup> groups) {
    final app = AppScope.read(context);
    final p = context.pal;
    final w = widget.work;
    final t = Theme.of(context).textTheme;
    final readable = groups.any((g) => g.variants.any(app.isPazuluReadable));

    final titleAndMeta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 7, runSpacing: 6, children: [
          Tag(w.type.label),
          // Status decided by the engine (AniList, MangaDex, sites, date of
          // the last chapter), not only the label of one source.
          Builder(builder: (context) {
            final d = app.seriesStatus(w);
            if (d.status == SeriesStatus.unknown) {
              return w.publicationStatus == null ? const SizedBox.shrink() : Tag(w.publicationStatus!);
            }
            return Tooltip(message: d.reason, child: Tag(d.status.label));
          }),
          if (w.year != null) Tag('${w.year}'),
        ]),
        const SizedBox(height: 12),
        Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: t.headlineLarge?.copyWith(fontSize: 32, height: 1.12)),
        if (w.altTitles.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(w.altTitles.take(2).join(' · '), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 13)),
        ],
        if (w.authors.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(w.authors.take(3).join(', '), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ],
    );

    final description = w.description.isEmpty ? const SizedBox.shrink() : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        AnimatedSize(
          duration: PazuluMotion.of(context, const Duration(milliseconds: 210)),
          alignment: Alignment.topLeft,
          child: Text(w.description, maxLines: _expanded ? null : 2,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(color: p.text.withValues(alpha: 0.83),
              height: 1.52, fontSize: 14)),
        ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(padding: EdgeInsets.zero,
            minimumSize: const Size(52, 36), alignment: Alignment.centerLeft),
          child: Text(_expanded ? 'Réduire le résumé' : 'Lire le résumé complet'),
        ),
      ],
    );

    final lastKey = entry?.progress.lastKey;
    final resumeLabel = lastKey == null ? null : ChapterKey.parse(lastKey).label;
    final primaryLabel = readable
        ? (resumeLabel != null ? 'Reprendre · $resumeLabel' : 'Commencer la lecture')
        : (_locatingReaders ? 'Recherche en cours…' : 'Chercher une source');

    final actions = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(220, 48),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            onPressed: readable ? () => _resume(groups)
              : (_locatingReaders ? null : _searchOtherReaders),
            icon: Icon(readable ? Icons.play_arrow_rounded : Icons.travel_explore_rounded),
            label: Text(primaryLabel),
          ),
          if (_nextUnread(groups, entry) case final int next when readable)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
              onPressed: () => _open(groups, next),
              icon: const Icon(Icons.skip_next_rounded, size: 20),
              label: Text('Suivant non lu · ${groups[next].key.label}'),
            ),
          SizedBox(width: 160, child: entry == null
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
                onPressed: () => app.addToLibrary(w),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Bibliothèque'))
            : _StatusMenu(entry: entry)),
          if (entry != null)
            _FavoriteButton(active: entry.favorite,
              onTap: () => app.updateEntry(w.id, (e) => e.favorite = !e.favorite)),
          // Secondary tools stay one click away, without cluttering the hero.
          PopupMenuButton<String>(
            tooltip: 'Sources et lecteurs',
            onSelected: (v) {
              if (v == 'link') _chooseNativeSource();
              if (v == 'more') _searchOtherReaders();
              if (v == 'site') _SavedSourcesSection(work: w)._add(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'link', child: ListTile(
                leading: Icon(Icons.library_books_outlined),
                title: Text('Ajouter un site par son lien'))),
              PopupMenuItem(value: 'more', enabled: !_locatingReaders, child: const ListTile(
                leading: Icon(Icons.travel_explore_rounded),
                title: Text('Chercher sur tous les sites'))),
              const PopupMenuItem(value: 'site', child: ListTile(
                leading: Icon(Icons.add_link_rounded),
                title: Text('Lier un site à la main'))),
            ],
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PazuluRadius.card),
                border: Border.all(color: p.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hub_outlined, size: 18, color: p.bright),
                const SizedBox(width: 8),
                const Text('Sources'),
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 18, color: p.muted),
              ]),
            ),
          ),
        ],
      ),
    );

    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleAndMeta,
        description,
        actions,
      ],
    );

    final cover = Hero(tag: widget.heroTag,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: p.ink, offset: const Offset(6, 6))]),
        child: CoverImage(url: w.coverUrl, radius: PazuluRadius.card)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 16, PazuluSpace.lg, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 660;
        final hero = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 200, child: cover),
              const SizedBox(width: 28),
              Expanded(child: detail),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: cover),
                const SizedBox(width: 16),
                Expanded(child: titleAndMeta),
              ]),
              description,
              actions,
            ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FadeSlideIn(index: 0, child: hero),
          const SizedBox(height: 20),
          _availabilityPanel(context, groups),
          if (w.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _genresExpanded = !_genresExpanded),
              icon: Icon(_genresExpanded
                ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
              label: Text(_genresExpanded ? 'Masquer les genres' : 'Genres et thèmes'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            if (_genresExpanded) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 6, runSpacing: 6,
                children: [for (final tag in w.tags.take(20)) Tag(tag)]),
            ),
          ],
        ]);
      }),
    );
  }

  /// Compact « Disponible » panel (Kiosque 2.4.1): only how many chapters
  /// exist in each language. Sites, per-site counts, search and the source
  /// audit are behind « Détails ».
  Widget _availabilityPanel(BuildContext context, List<ChapterGroup> groups) {
    final app = AppScope.of(context);
    final p = context.pal;
    final lookup = app.readerLookupProgress[widget.work.id];
    const names = {'en': 'Anglais', 'fr': 'Français'};

    ({int count, int specials, double? last, List<MapEntry<String, int>> ranked}) stats(String lang) {
      final perSource = <String, int>{};
      final keys = <String>{};
      // Whole-number chapters vs. extras (0, 12.5, side stories).
      var specials = 0;
      // A chapter announced by one site only (« non confirmé ») is neither
      // counted nor the « dernier » chapter.
      bool unconfirmed(ChapterGroup g) => app.isAheadUnconfirmed(widget.work.id, lang, g.key.id);
      double? last;
      for (final g in groups) {
        if (unconfirmed(g)) continue;
        var has = false;
        for (final v in g.variants) {
          if (v.isExternal || v.lang != lang) continue;
          has = true;
          if (keys.add(g.key.id)) {
            final n = g.key.number;
            if (n == null || n < 1 || n != n.roundToDouble()) specials++;
          }
          final name = v.group.isNotEmpty ? v.group : app.sourceName(v.sourceId);
          perSource[name] = (perSource[name] ?? 0) + 1;
        }
        final n = g.key.number;
        if (has && n != null && (last == null || n > last)) last = n;
      }
      final ranked = perSource.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return (count: keys.length - specials, specials: specials, last: last, ranked: ranked);
    }

    String num(double n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
    final langs = app.settings.comicLangs;
    final all = {for (final l in langs) l: stats(l)};

    Widget countBlock(String lang) {
      final st = all[lang]!;
      final empty = st.count == 0 && st.specials == 0;
      final fr = lang == 'fr';
      return Tooltip(
        message: empty
            ? '${names[lang] ?? lang}: aucun chapitre trouvé pour l’instant'
            : '${names[lang] ?? lang}: ${st.count} chapitres'
                '${st.specials > 0 ? ' + ${st.specials} spéciaux' : ''}'
                '${st.last == null ? '' : ' · dernier : ch. ${num(st.last!)}'}',
        child: Container(
          decoration: kiosqueBox(p, color: empty ? p.surfaceHigh : p.surface, shadow: empty ? 0 : 3, width: 2.5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: empty ? p.surfaceHigh : (fr ? p.accent : p.ink),
                border: Border(right: BorderSide(color: p.ink, width: 2.5)),
              ),
              child: Text(lang.toUpperCase(), style: kiosqueDisplay(15,
                  color: empty ? p.muted : (fr ? p.onAccent : p.background))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                Text(empty ? '—' : '${st.count}', style: kiosqueDisplay(24, color: empty ? p.muted : p.text)),
                const SizedBox(width: 5),
                Text(st.count > 1 ? 'CHAPITRES' : 'CHAPITRE',
                    style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ]),
            ),
          ]),
        ),
      );
    }

    final siteCount = {for (final st in all.values) for (final e in st.ranked) e.key}.length;
    final searching = lookup != null && lookup.total > 0;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: kiosqueBox(p, shadow: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('DISPONIBLE', style: kiosqueDisplay(17, color: p.text)),
          if (groups.isEmpty && !searching)
            Text('Aucun chapitre trouvé pour l’instant.', style: TextStyle(color: p.muted, fontSize: 13))
          else
            for (final lang in langs) countBlock(lang),
          if (lookup != null && lookup.total > 0)
            SizedBox(
              width: 160,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RECHERCHE ${lookup.done}/${lookup.total} SITES',
                    style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                InkBar(value: lookup.ratio, height: 8),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _availabilityExpanded = !_availabilityExpanded),
          icon: Icon(_availabilityExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
          label: Text(_availabilityExpanded
              ? 'MASQUER LES DÉTAILS'
              : 'DÉTAILS · $siteCount SITE${siteCount > 1 ? 'S' : ''}'),
          style: TextButton.styleFrom(
            foregroundColor: p.muted,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            alignment: Alignment.centerLeft,
          ),
        ),
        AnimatedSize(
          duration: PazuluMotion.of(context, const Duration(milliseconds: 240)),
          curve: PazuluMotion.curve,
          alignment: Alignment.topCenter,
          child: !_availabilityExpanded
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final lang in langs)
                    if (all[lang]!.ranked.isNotEmpty) Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 34, child: LangBadge(lang)),
                        Expanded(child: Text(
                          [
                            if (all[lang]!.specials > 0) '+ ${all[lang]!.specials} spéciaux',
                            if (all[lang]!.last != null) 'dernier : ch. ${num(all[lang]!.last!)}',
                            [for (final e in all[lang]!.ranked) '${e.key} (${e.value})'].join(' · '),
                          ].join(' — '),
                          style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
                        )),
                      ]),
                    ),
                  Wrap(spacing: 18, children: [
                    if (!searching)
                      TextButton.icon(
                        onPressed: _locatingReaders ? null : _searchOtherReaders,
                        icon: const Icon(Icons.travel_explore_rounded, size: 16),
                        label: const Text('CHERCHER D’AUTRES SITES'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      ),
                    TextButton.icon(
                      onPressed: _chooseNativeSource,
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: const Text('AJOUTER UN SITE PAR SON LIEN'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    ),
                  ]),
                  _sourceAudit(context),
                ]),
        ),
      ]),
    );
  }

  Widget _sourceAudit(BuildContext context) {
    final checks = AppScope.read(context).catalogueChecksFor(widget.work.id);
    if (checks.isEmpty) return const SizedBox.shrink();
    final p = context.pal;
    final failed = checks.where((c) => c.state == CatalogueCheckState.failed).length;
    final succeeded = checks.where((c) => c.confirmed).length;
    // Every source that answered, side by side (all at the same level):
    // name, readable chapters, and the latest chapter it offers.
    final ok = [for (final c in checks) if (c.confirmed && c.readable > 0) c]
      ..sort((a, b) => b.readable.compareTo(a.readable));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (ok.isNotEmpty) ...[
          Text('Sites (${ok.length}) — clic pour bloquer un site',
              style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in ok.take(12))
              PopupMenuButton<String>(
                tooltip: 'Options de ${c.name}',
                onSelected: (v) {
                  if (v != 'block') return;
                  AppScope.read(context).blockSource(c.sourceId);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${c.name} est bloquée partout. Réglages › Sources bloquées pour annuler.'),
                  ));
                  _refresh();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'block', child: ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: Text('Bloquer ${c.name}'),
                    subtitle: const Text('Mauvaise langue, mauvaise qualité…'),
                  )),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border.all(color: p.ink, width: 2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_stories_outlined, size: 14, color: p.text),
                    const SizedBox(width: 6),
                    Text(c.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text('${c.readable} ch.', style: TextStyle(color: p.muted, fontSize: 12)),
                    const SizedBox(width: 2),
                    Icon(Icons.more_vert_rounded, size: 14, color: p.muted),
                  ]),
                ),
              ),
            if (ok.length > 12) Tag('+${ok.length - 12}'),
          ]),
        ],
        TextButton.icon(
          onPressed: () => setState(() => _auditExpanded = !_auditExpanded),
          icon: Icon(_auditExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          label: Text('Détails des sources · $succeeded vérifiée(s)'
            '${failed == 0 ? '' : ' · $failed à revérifier'}'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        if (_auditExpanded) Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final check in checks) Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(check.state == CatalogueCheckState.failed
                  ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                  size: 17, color: check.state == CatalogueCheckState.failed ? p.muted : p.bright),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(check.name, style: TextStyle(color: p.text,
                    fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(check.state == CatalogueCheckState.checked
                    ? '${check.observed} entrées recensées, ${check.readable} lisibles dans Pazulu'
                    : check.state == CatalogueCheckState.failed
                      ? 'Vérification impossible · ${check.detail ?? 'réessayer'}'
                      : check.state == CatalogueCheckState.empty
                        ? 'Aucun chapitre retourné par ce catalogue'
                        : 'Aucun connecteur de lecture disponible',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 6),
            Text('Un catalogue incomplet ne signifie pas que les autres chapitres n’existent pas.',
              style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  // -------------------------------------------------------------------------
  // Chapitres
  // -------------------------------------------------------------------------

  Widget _chapterToolbar(BuildContext context, List<ChapterGroup> groups) {
    final p = context.pal;
    Widget pill(String label, _ChapterFilter f) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _MiniPill(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.xl, PazuluSpace.lg, PazuluSpace.md),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Text(groups.isEmpty ? 'Chapitres' : 'Chapitres', style: Theme.of(context).textTheme.titleLarge),
          if (groups.isNotEmpty) ...[
            const SizedBox(width: 10),
            Tag('${groups.length}'),
          ],
          const SizedBox(width: PazuluSpace.lg),
          pill('Tous', _ChapterFilter.all),
          pill('EN', _ChapterFilter.en),
          pill('FR', _ChapterFilter.fr),
          pill('Non lus', _ChapterFilter.unread),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _newestFirst ? 'Plus anciens d\'abord' : 'Plus récents d\'abord',
            icon: Icon(_newestFirst ? Icons.south_rounded : Icons.north_rounded, color: p.text),
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
          if (groups.isNotEmpty) ...[
            IconButton(
              tooltip: 'Aller au chapitre…',
              icon: Icon(Icons.pin_outlined, color: p.text),
              onPressed: () => _jumpTo(groups),
            ),
            IconButton(
              tooltip: 'Marquer comme lus jusqu\'au chapitre…',
              icon: Icon(Icons.done_all_rounded, color: p.text),
              onPressed: () => _markUpTo(groups),
            ),
          ],
          const SizedBox(width: PazuluSpace.lg),
          _languagePicker(context),
        ],
      ),
    );
  }

  /// « Lire en : Auto · EN · FR » — which language opens when a chapter is
  /// clicked, remembered for the work when it is in the library.
  Widget _languagePicker(BuildContext context) {
    final app = AppScope.of(context);
    final entry = app.entry(widget.work.id);
    final current = _langChoice ?? entry?.preferredLang ?? 'auto';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Lire en', style: TextStyle(color: context.pal.muted, fontSize: 13)),
      const SizedBox(width: 8),
      SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          const ButtonSegment(value: 'auto', label: Text('Auto')),
          for (final l in app.settings.comicLangs)
            ButtonSegment(value: l, label: Text(l.toUpperCase())),
        ],
        selected: {app.settings.comicLangs.contains(current) ? current : 'auto'},
        onSelectionChanged: (v) {
          final lang = v.first == 'auto' ? null : v.first;
          setState(() => _langChoice = lang);
          app.setPreferredLang(widget.work, lang);
        },
      ),
    ]);
  }

  List<Widget> _chapterSlivers(
    BuildContext context,
    AsyncSnapshot<List<ChapterGroup>> snap,
    List<ChapterGroup> groups,
    LibraryEntry? entry,
  ) {
    // While a newer list loads, the current one stays visible (no grey
    // placeholders over 285 chapters already known).
    if (snap.connectionState != ConnectionState.done && !snap.hasData) {
      return [
        SliverList.builder(
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.sm),
            child: Pulse(height: 64),
          ),
        ),
      ];
    }
    if (snap.hasError) {
      return [SliverToBoxAdapter(child: Column(children: [
        ErrorState(error: snap.error!, onRetry: _refresh),
        TextButton.icon(
          onPressed: _locatingReaders ? null : _searchOtherReaders,
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('Chercher l\'œuvre sur tous les sites'),
        ),
      ]))];
    }
    if (groups.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.menu_book_outlined,
            title: widget.work.id.startsWith('manual:')
                ? 'Fiche personnelle' : 'Aucun chapitre dans vos langues',
            message: widget.work.id.startsWith('manual:')
                ? 'Cette œuvre est enregistrée localement. Lie ses sites ci-dessus '
                  'pour les retrouver rapidement ; les chapitres ne sont pas '
                  'encore importés depuis ces sites.'
                : 'Aucune des sources interrogées ne propose encore de chapitre EN ou FR. '
                  'Pazulu recommence la recherche sur tous les sites toutes les 12 h.',
            action: FilledButton.icon(
              onPressed: _locatingReaders ? null : _searchOtherReaders,
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(_locatingReaders ? 'Recherche en cours…' : 'Chercher sur tous les sites'),
            ),
          ),
        ),
      ];
    }

    final app = AppScope.read(context);
    final read = entry?.progress.readKeys ?? const <String>{};
    final indexed = <(int, ChapterGroup)>[
      for (var i = 0; i < groups.length; i++)
        if (switch (_filter) {
          _ChapterFilter.all => true,
          // Every source counts the same: a chapter listed in French by a
          // site is a French chapter (only release notifications wait for a
          // second source).
          _ChapterFilter.en => groups[i].variants.any((v) => v.lang == 'en'),
          _ChapterFilter.fr => groups[i].variants.any((v) => v.lang == 'fr'),
          _ChapterFilter.unread => !read.contains(groups[i].key.id),
        })
          (i, groups[i]),
    ];
    final ordered = _newestFirst ? indexed.reversed.toList() : indexed;

    if (ordered.isEmpty) {
      return const [
        SliverToBoxAdapter(child: EmptyState(icon: Icons.filter_alt_off_outlined, title: 'Aucun chapitre pour ce filtre')),
      ];
    }

    return [
      SliverList.builder(
        itemCount: ordered.length,
        itemBuilder: (context, i) {
          final (index, g) = ordered[i];
          final ranked = rankVariants(
            g.variants,
            langs: app.settings.comicLangs,
            preferredLang: _langChoice ?? entry?.preferredLang,
            preferredGroup: entry?.preferredGroup,
            preferredSourceId: entry?.preferredSourceId,
          );
          final routed = app.usableReaders(ranked,
              preferredLang: _langChoice ?? entry?.preferredLang);
          final isCurrent = entry?.progress.lastKey == g.key.id;
          final downloadable = routed.where(app.isPazuluReadable).toList();
          final saved = g.variants.map((v) => app.downloadOf(v.chapterId)).whereType<Object>().isNotEmpty;
          final pending = g.variants.map((v) => app.downloading[v.chapterId]).whereType<double>().toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.sm),
            child: FadeSlideIn(
              index: i < 5 ? i : 5,
              child: _ChapterRow(
                group: g,
                readers: routed,
                unavailableChapterIds: _unavailableExternalLinks,
                isUnconfirmed: (c) => app.isLangUnconfirmed(widget.work.id, c.chapterId),
                fallbackDate: g.firstDate == null ? app.fallbackReleaseDate(widget.work, g) : null,
                aheadUnconfirmed: g.variants.any((v) => !v.isExternal) &&
                    g.variants.where((v) => !v.isExternal).every((v) =>
                        app.isAheadUnconfirmed(widget.work.id, v.lang, g.key.id)),
                read: read.contains(g.key.id),
                current: isCurrent,
                currentPage: isCurrent ? (entry?.progress.lastPage ?? 0) : null,
                onOpen: (selected) {
                  // Tapping the chapter row passes null; a reader chip passes a
                  // specific variant. Choose the preferred reader for the row.
                  final v = selected ?? routed.where(app.isPazuluReadable).firstOrNull
                    ?? (routed.isEmpty ? null : routed.first);
                  if (v == null) {
                    resumeInPazulu(context, widget.work, chapterHint: g.key.id);
                    return;
                  }
                  if (!app.isPazuluReadable(v)) {
                    // Explicit confirmation for external/paywalled/404 links.
                    if (!v.isExternal) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Connecteur indisponible : une autre version doit être choisie.'),
                      ));
                    } else {
                      _openExternalChapter(v, g, groups, index);
                    }
                    return;
                  }
                  _open(groups, index,
                      page: isCurrent ? (entry?.progress.lastPage ?? 0) : 0,
                      variant: v);
                },
                onToggleRead: () => app.setRead(widget.work, [g.key], !read.contains(g.key.id)),
                download: downloadable.isEmpty
                    ? null
                    : _DownloadState(
                        saved: saved,
                        progress: pending.isEmpty ? null : pending.first,
                        onTap: () => _toggleDownload(g, downloadable.first),
                      ),
                onMarkPrevious: () {
                  app.setRead(widget.work, groups.take(index + 1).map((x) => x.key), true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${index + 1} chapitres marqués comme lus')),
                  );
                },
              ),
            ),
          );
        },
      ),
    ];
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PazuluRadius.chip),
        child: AnimatedContainer(
          duration: PazuluMotion.of(context, PazuluMotion.hover),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? p.text : Colors.transparent,
            borderRadius: BorderRadius.circular(PazuluRadius.chip),
            border: Border.all(color: selected ? p.text : p.borderStrong),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? p.background : p.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const pink = Color(0xFFF472B6);
    return Tooltip(
      message: active ? 'Retirer des favoris' : 'Ajouter aux favoris',
      child: Material(
        color: active ? pink : p.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: p.ink, width: 2.5)),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: AnimatedSwitcher(
              duration: PazuluMotion.of(context, const Duration(milliseconds: 220)),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(
                active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(active),
                color: active ? const Color(0xFF111111) : p.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final p = context.pal;
    return PopupMenuButton<TrackStatus>(
      tooltip: 'Statut de suivi',
      initialValue: entry.status,
      onSelected: (s) => app.updateEntry(entry.work.id, (e) => e.status = s),
      itemBuilder: (_) => [for (final s in TrackStatus.values) PopupMenuItem(value: s, child: Text(s.label))],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.borderStrong),
        ),
        child: Row(
          children: [
            Icon(Icons.bookmark_rounded, size: 18, color: p.bright),
            const SizedBox(width: 8),
            Expanded(child: Text(entry.status.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatefulWidget {
  const _ChapterRow({
    required this.group,
    required this.readers,
    required this.unavailableChapterIds,
    required this.read,
    required this.current,
    required this.currentPage,
    required this.onOpen,
    required this.onToggleRead,
    required this.onMarkPrevious,
    required this.isUnconfirmed,
    this.aheadUnconfirmed = false,
    this.fallbackDate,
    this.download,
  });

  /// Date when no site writes one next to the chapter (feeds, first seen).
  final (DateTime, String)? fallbackDate;

  /// Announced by one site only, ahead of every other site.
  final bool aheadUnconfirmed;

  final _DownloadState? download;

  /// Language claimed by a single source ahead of all others (« FR ? »).
  final bool Function(SourceChapter) isUnconfirmed;
  final ChapterGroup group;
  final List<SourceChapter> readers;
  final Set<String> unavailableChapterIds;
  final bool read;
  final bool current;
  final int? currentPage;
  final ValueChanged<SourceChapter?> onOpen;
  final VoidCallback onToggleRead;
  final VoidCallback onMarkPrevious;

  @override
  State<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends State<_ChapterRow> {
  bool _hover = false;

  void _showAllReaders() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            children: [
              Text('Chapitre ${widget.group.key.label} · Toutes les versions',
                style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Une version externe peut demander un abonnement ou etre indisponible. '
                'Seules les versions natives se chargent dans notre lecteur.'),
              const SizedBox(height: 12),
              for (var i = 0; i < widget.readers.length; i++)
                ListTile(
                  leading: Icon(widget.readers[i].isExternal
                    ? Icons.open_in_browser_rounded : Icons.menu_book_rounded),
                  title: Text(widget.readers[i].isExternal
                    ? 'Lien externe ${i + 1} · ${widget.readers[i].langLabel}'
                    : 'Lecteur ${i + 1} · ${widget.readers[i].langLabel}'),
                  subtitle: Text('${widget.readers[i].group}'
                    '${widget.unavailableChapterIds.contains(widget.readers[i].chapterId) ? ' · signale indisponible' : ''}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onOpen(widget.readers[i]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Chapter 115" next to "Chapitre 115" says nothing: hide such titles.
  static bool _redundantTitle(String? title, String keyId) {
    if (title == null) return true;
    final t = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), ' ').trim();
    return t.isEmpty || RegExp('^(?:chapter|chapitre|ch|episode|ep)? ?${RegExp.escape(keyId)}\$')
        .hasMatch(t);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final g = widget.group;
    final title = _redundantTitle(g.title, g.key.id) ? null : g.title;
    final fallback = widget.fallbackDate;
    final released = g.firstDate ?? fallback?.$1;
    final isNew = released != null && !widget.aheadUnconfirmed &&
        DateTime.now().difference(released) < const Duration(days: 7) && !widget.read;
    final meta = [
      if (widget.current) 'En cours · page ${(widget.currentPage ?? 0) + 1}'
      else if (widget.read) 'Lu',
      if (released != null)
        releaseLine(released, verb: g.firstDate == null ? (fallback?.$2 ?? 'Sorti') : 'Sorti')
      else
        'Date de sortie inconnue',
    ].join(' · ');

    final native = widget.readers.where((v) => !v.isExternal).toList();
    final external = widget.readers.length - native.length;
    final langs = <String>{for (final v in native) v.lang}.toList()..sort();
    // Notifications still wait for a 2nd source; the list shows the language
    // the site gives (the user reads it and judges).
    const doubtful = <String>[];
    final number = g.key.number != null ? g.key.id : g.key.label;

    final readers = Tooltip(
      message: native.isNotEmpty
          ? '${native.length} lecteur(s) Pazulu · ${widget.readers.length} version(s)'
          : '$external lien(s) éditeur, sans pages intégrées',
      child: TextButton.icon(
        onPressed: widget.readers.isEmpty ? null : _showAllReaders,
        style: TextButton.styleFrom(
          foregroundColor: native.isNotEmpty ? p.bright : p.muted,
          minimumSize: const Size(44, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: Icon(native.isNotEmpty ? Icons.auto_stories_outlined : Icons.link_rounded, size: 16),
        label: Text(native.isNotEmpty ? '${native.length}' : 'Externe',
            style: const TextStyle(fontSize: 13)),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: PazuluMotion.of(context, PazuluMotion.hover),
        decoration: BoxDecoration(
          color: widget.current
              ? p.selected
              : (_hover ? p.surfaceHigh : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onOpen(null),
            onLongPress: widget.onMarkPrevious,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  // Current chapter: an accent bar, not a glowing dot.
                  AnimatedContainer(
                    duration: PazuluMotion.of(context, PazuluMotion.hover),
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: widget.current ? p.bright : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: widget.read && !widget.current ? p.muted : p.text,
                        )),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(child: Text(title ?? g.key.longLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: widget.read && !widget.current ? p.muted : p.text,
                              ))),
                          if (widget.aheadUnconfirmed) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Un seul site annonce ce chapitre, les autres s\'arrêtent avant '
                                  '(autre numérotation, fin de saison…).',
                              child: Text('1 site · non confirmé', style: TextStyle(
                                  color: p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ],
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: p.success.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(PazuluRadius.chip),
                              ),
                              child: Text('NOUVEAU', style: TextStyle(color: p.success,
                                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                            ),
                          ],
                        ]),
                        if (meta.isNotEmpty)
                          Text(meta, style: TextStyle(
                              color: widget.current ? p.bright : p.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  for (final l in langs.take(3))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: LangBadge(l, dimmed: widget.read && !widget.current),
                    ),
                  for (final l in doubtful.take(2))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: 'Une seule source annonce ce chapitre en ${l.toUpperCase()}, '
                            'en avance sur toutes les autres : langue non confirmée.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: p.warning.withValues(alpha: 0.7)),
                          ),
                          child: Text('${l.toUpperCase()} ?', style: TextStyle(
                              color: p.warning, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  readers,
                  if (widget.download != null) _DownloadButton(state: widget.download!),
                  IconButton(
                    tooltip: widget.read ? 'Marquer comme non lu' : 'Marquer comme lu',
                    icon: Icon(widget.read ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 20, color: widget.read ? p.success : p.muted),
                    onPressed: widget.onToggleRead,
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

class _DownloadState {
  const _DownloadState({required this.saved, required this.progress, required this.onTap});

  final bool saved;
  final double? progress;
  final VoidCallback onTap;
}

/// Télécharger / en cours / disponible hors ligne.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.state});

  final _DownloadState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final progress = state.progress;
    if (progress != null) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(value: progress <= 0 ? null : progress, strokeWidth: 2.5),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: state.saved ? 'Disponible hors ligne — retirer' : 'Télécharger pour lire hors ligne (.cbz)',
      onPressed: state.onTap,
      icon: Icon(
        state.saved ? Icons.offline_pin_rounded : Icons.download_rounded,
        color: state.saved ? p.bright : p.muted,
      ),
    );
  }
}


/// Liens par œuvre vers les autres sources du catalogue.
/// Conservés dans la bibliothèque et donc dans les sauvegardes .pazulu.
class _SavedSourcesSection extends StatelessWidget {
  const _SavedSourcesSection({required this.work});

  final WorkInfo work;

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final controller = TextEditingController();
    var selectedSite = app.activeSources.first.id;
    var selectedLang = 'en';
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Lier un site à cette œuvre'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search is essential when the directory contains 200 sites:
                // no giant unfiltered DropdownButton that blocks navigation.
                DropdownMenu<String>(
                  width: 412,
                  menuHeight: 300,
                  enableFilter: true,
                  enableSearch: true,
                  initialSelection: selectedSite,
                  label: const Text('Rechercher une source'),
                  dropdownMenuEntries: [
                    for (final site in app.activeSources)
                      DropdownMenuEntry(value: site.id, label: site.title),
                  ],
                  onSelected: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedSite = value;
                      selectedLang = app.siteById(value)!.languages.first;
                      error = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedSite),
                  initialValue: selectedLang,
                  decoration: const InputDecoration(labelText: 'Langue'),
                  items: [
                    for (final lang in const ['en', 'fr'])
                      DropdownMenuItem(value: lang, child: Text(lang.toUpperCase())),
                  ],
                  onChanged: (value) {
                    if (value != null) selectedLang = value;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Adresse de la fiche de cette œuvre',
                    hintText: 'https://…',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final ok = app.addSiteLink(work, selectedSite, controller.text, selectedLang);
                if (ok) {
                  Navigator.pop(dialogContext);
                } else {
                  setDialogState(() => error = 'Lien HTTPS invalide ou appartenant à un autre site.');
                }
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final saved = app.entry(work.id)?.savedSiteLinks ?? const <SavedSiteLink>[];
    // Nothing linked by hand: no empty box (« Lier un site » is in Sources).
    if (saved.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.sm, PazuluSpace.lg, PazuluSpace.md),
      child: Glass(
        padding: const EdgeInsets.all(PazuluSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(saved.isEmpty ? 'Sources liées · aucune' : 'Sources liées · ${saved.length}', style: TextStyle(
                  color: p.bright, fontSize: 12, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ))),
                TextButton.icon(
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('Lier un site'),
                  onPressed: () => _add(context),
                ),
              ],
            ),
            for (final link in saved)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.language_rounded, color: p.bright),
                title: Text(app.siteById(link.siteId)?.title ?? link.siteId),
                subtitle: Text('${link.lang.toUpperCase()} · ${link.url}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: (app.siteById(link.siteId)?.accepts(link.url) ?? false)
                    ? () => pushPage(context, SourceBrowserPage(
                        title: app.siteById(link.siteId)?.title ?? link.siteId,
                        url: link.url, siteId: link.siteId,
                      ))
                    : null,
                trailing: IconButton(
                  tooltip: 'Retirer ce lien',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => app.removeSiteLink(work.id, link),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
