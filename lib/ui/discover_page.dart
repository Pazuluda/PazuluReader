import 'package:flutter/material.dart';

import '../core/anime/anilist.dart';
import '../core/anime/crunchyroll.dart';
import '../core/app_state.dart';
import '../core/discovery.dart';
import '../core/log.dart';
import '../core/models.dart';
import '../core/site_index.dart';
import '../core/work_status.dart';
import '../design/theme.dart';
import 'anime_page.dart';
import 'app_scope.dart';
import 'format.dart';
import 'widgets/crunchyroll_actions.dart';
import 'widgets/common.dart';
import 'widgets/entry_actions.dart';
import 'widgets/motion.dart';
import 'work_page.dart';
import 'sources_page.dart';

/// Découvrir : la recherche interroge OBLIGATOIREMENT toutes les sources
/// (connecteurs, extensions et chaque site du répertoire), résultats affichés
/// au fil de l'eau. Sans recherche : populaires + œuvres de tous les sites.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

enum _Mode { reads, anime }

/// A search asked from elsewhere (Ctrl+K « Chercher partout »).
final ValueNotifier<String?> discoverSearchRequest = ValueNotifier<String?>(null);

/// What Discover shows below the search (one at a time: readable).
enum _Section { trending, popular, top, fresh, ongoing, hiatus, cancelled, completed, sites, titles }

class _SectionInfo {
  const _SectionInfo(this.label, this.subtitle, this.icon, this.colors, {this.sort, this.status});

  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String? sort;
  final SeriesStatus? status;
}

const _sections = <_Section, _SectionInfo>{
  _Section.trending: _SectionInfo('Tendances', 'Ce qui se lit en ce moment', Icons.local_fire_department_rounded,
      [Color(0xFFF97316), Color(0xFFDB2777)], sort: 'TRENDING_DESC'),
  _Section.popular: _SectionInfo('Populaires', 'Les plus suivies', Icons.groups_rounded,
      [Color(0xFF6366F1), Color(0xFF8B5CF6)], sort: 'POPULARITY_DESC'),
  _Section.top: _SectionInfo('Mieux notées', 'Les meilleures notes', Icons.star_rounded,
      [Color(0xFFEAB308), Color(0xFFF59E0B)], sort: 'SCORE_DESC'),
  _Section.fresh: _SectionInfo('Nouveautés', 'Séries récentes', Icons.fiber_new_rounded,
      [Color(0xFF10B981), Color(0xFF059669)], sort: 'START_DATE_DESC'),
  _Section.ongoing: _SectionInfo('En cours', 'La publication continue', Icons.play_circle_outline_rounded,
      [Color(0xFF0EA5E9), Color(0xFF2563EB)], status: SeriesStatus.ongoing),
  _Section.hiatus: _SectionInfo('En pause', 'Hiatus', Icons.pause_circle_outline_rounded,
      [Color(0xFF64748B), Color(0xFF475569)], status: SeriesStatus.hiatus),
  _Section.cancelled: _SectionInfo('Annulées', 'Axed / abandonnées', Icons.cancel_outlined,
      [Color(0xFFEF4444), Color(0xFFB91C1C)], status: SeriesStatus.cancelled),
  _Section.completed: _SectionInfo('Terminées', 'À lire d\'une traite', Icons.flag_rounded,
      [Color(0xFF14B8A6), Color(0xFF0D9488)], status: SeriesStatus.completed),
  _Section.sites: _SectionInfo('Sur les sites', 'Accueil de chaque site', Icons.language_rounded,
      [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
  _Section.titles: _SectionInfo('Tous les titres', 'Catalogues complets A → Z', Icons.sort_by_alpha_rounded,
      [Color(0xFF334155), Color(0xFF1E293B)]),
};

const _genreIcons = <String, IconData>{
  'Action': Icons.sports_martial_arts_rounded, 'Adventure': Icons.explore_rounded,
  'Comedy': Icons.sentiment_very_satisfied_rounded, 'Drama': Icons.theater_comedy_rounded,
  'Fantasy': Icons.auto_fix_high_rounded, 'Horror': Icons.dark_mode_rounded,
  'Mystery': Icons.search_rounded, 'Psychological': Icons.psychology_rounded,
  'Romance': Icons.favorite_rounded, 'Sci-Fi': Icons.rocket_launch_rounded,
  'Slice of Life': Icons.local_cafe_rounded, 'Sports': Icons.sports_soccer_rounded,
  'Supernatural': Icons.whatshot_rounded, 'Thriller': Icons.bolt_rounded,
  'Mecha': Icons.precision_manufacturing_rounded, 'Music': Icons.music_note_rounded,
};

enum _ResultSort { relevance, sources, title }

class _DiscoverPageState extends State<DiscoverPage> {
  final _controller = TextEditingController();
  _Mode _mode = _Mode.reads;

  // Catalogue (AniList metadata: genres, score, status, chapters).
  static const _sorts = {
    'TRENDING_DESC': 'Tendances',
    'POPULARITY_DESC': 'Populaires',
    'SCORE_DESC': 'Mieux notés',
    'START_DATE_DESC': 'Nouveautés',
  };
  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural',
    'Thriller', 'Mecha', 'Music',
  ];
  static const _genreFr = {
    'Action': 'Action', 'Adventure': 'Aventure', 'Comedy': 'Comédie', 'Drama': 'Drame',
    'Fantasy': 'Fantasy', 'Horror': 'Horreur', 'Mystery': 'Mystère',
    'Psychological': 'Psychologique', 'Romance': 'Romance', 'Sci-Fi': 'Science-fiction',
    'Slice of Life': 'Tranche de vie', 'Sports': 'Sport', 'Supernatural': 'Surnaturel',
    'Thriller': 'Thriller', 'Mecha': 'Mecha', 'Music': 'Musique',
  };
  _Section _section = _Section.trending;
  bool _hideMine = false;
  _ResultSort _resultSort = _ResultSort.relevance;
  String? _resultType;
  final _scroll = ScrollController();
  final _searchFocus = FocusNode();
  String _typing = '';

  void _onExternalSearch() {
    final q = discoverSearchRequest.value;
    if (q == null || !mounted) return;
    discoverSearchRequest.value = null;
    _setMode(_Mode.reads);
    _controller.text = q;
    _submit(q);
  }

  @override
  void initState() {
    super.initState();
    discoverSearchRequest.addListener(_onExternalSearch);
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onExternalSearch());
  }

  void _selectSection(_Section s) {
    final info = _sections[s]!;
    setState(() {
      _section = s;
      if (info.status != null) _statusTab = info.status!;
    });
    if (info.sort != null && info.sort != _sort) {
      _sort = info.sort!;
      _loadCatalog(reset: true);
    }
  }

  bool _isMine(AppState app, WorkInfo w) => app.inLibrary(w.id) ||
      app.entries.any((e) => sameWorkAcrossSources(e.work,
          WorkInfo(id: w.id, title: w.title, altTitles: w.altTitles, type: w.type)));

  List<WorkInfo> _visible(AppState app, List<WorkInfo> works) =>
      _hideMine ? [for (final w in works) if (!_isMine(app, w)) w] : works;

  /// Pretty category tiles (one click = one section).
  Widget _sectionTiles() {
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 4, PazuluSpace.lg, 8),
        children: [
          for (final e in _sections.entries)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _CategoryTile(info: e.value, selected: _section == e.key,
                  fill: _tileFills[e.key.index % _tileFills.length],
                  onTap: () => _selectSection(e.key)),
            ),
        ],
      ),
    );
  }

  /// Instant suggestions while typing: the library and every site's
  /// catalogue answer before the search of all sources.
  Widget _suggestions(AppState app) {
    final p = context.pal;
    final q = SiteTitleIndex.norm(_typing);
    if (!_searchFocus.hasFocus) return const SizedBox.shrink();
    if (q.isEmpty) {
      final recent = app.settings.recentSearches;
      if (recent.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Icon(Icons.history_rounded, size: 16, color: p.muted),
          for (final r in recent.take(8))
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(r),
              onPressed: () {
                _controller.text = r;
                _submit(r);
              },
            ),
          TextButton(onPressed: app.clearRecentSearches, child: const Text('Effacer')),
        ]),
      );
    }
    if (q.length < 2 || _typing.trim() == _lastQuery) return const SizedBox.shrink();
    final hits = <(String, String, VoidCallback)>[];
    for (final e in app.entries) {
      if (hits.length >= 4) break;
      if (SiteTitleIndex.norm(e.work.title).contains(q) ||
          e.work.altTitles.any((t) => SiteTitleIndex.norm(t).contains(q))) {
        hits.add((e.work.title, 'Dans ma bibliothèque', () =>
            pushPage(context, WorkPage(work: e.work, heroTag: 'sugg-${e.work.id}'))));
      }
    }
    final works = app.siteIndex.works;
    if (works == null) {
      app.siteIndex.prepareWorks().then((_) {
        if (mounted) setState(() {});
      });
    } else {
      // Titles starting with the text first, then containing it.
      final starts = <IndexedWork>[];
      final contains = <IndexedWork>[];
      for (final w in works) {
        if (starts.length >= 8) break;
        if (w.key.startsWith(q)) {
          starts.add(w);
        } else if (contains.length < 8 && w.key.contains(q)) {
          contains.add(w);
        }
      }
      for (final w in [...starts, ...contains].take(8 - hits.length)) {
        hits.add((w.title, '${w.links.length} site${w.links.length > 1 ? 's' : ''}', () =>
            pushPage(context, WorkPage(work: w.toWork(), heroTag: 'sugg-${w.key}'))));
      }
    }
    if (hits.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(PazuluRadius.card),
        border: Border.all(color: p.border),
      ),
      child: Column(children: [
        for (final (title, sub, open) in hits)
          ListTile(
            dense: true,
            leading: Icon(sub.startsWith('Dans') ? Icons.collections_bookmark_rounded : Icons.public_rounded,
                size: 18, color: p.bright),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(sub, style: TextStyle(color: p.muted, fontSize: 12)),
            onTap: open,
          ),
        ListTile(
          dense: true,
          leading: Icon(Icons.travel_explore_rounded, size: 18, color: p.bright),
          title: Text('Chercher « ${_typing.trim()} » sur toutes les sources'),
          onTap: () => _submit(_controller.text),
        ),
      ]),
    );
  }

  /// Filters of the search results.
  Widget _resultFilters() {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, 4),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final t in const [null, ContentType.manga, ContentType.manhwa, ContentType.manhua])
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(t == null ? 'Tous les types' : t.label),
            selected: _resultType == t?.name,
            onSelected: (_) => setState(() => _resultType = t?.name),
          ),
        const SizedBox(width: 8),
        PopupMenuButton<_ResultSort>(
          tooltip: 'Trier les résultats',
          initialValue: _resultSort,
          onSelected: (v) => setState(() => _resultSort = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: _ResultSort.relevance, child: Text('Pertinence')),
            PopupMenuItem(value: _ResultSort.sources, child: Text('Le plus de sites')),
            PopupMenuItem(value: _ResultSort.title, child: Text('Titre (A → Z)')),
          ],
          child: Chip(
            avatar: Icon(Icons.sort_rounded, size: 16, color: p.text),
            label: Text(switch (_resultSort) {
              _ResultSort.relevance => 'Pertinence',
              _ResultSort.sources => 'Le plus de sites',
              _ResultSort.title => 'Titre (A → Z)',
            }),
          ),
        ),
      ]),
    );
  }

  List<WorkInfo> _sortedResults(AppState app) {
    var list = _visible(app, _results);
    if (_resultType != null) list = [for (final w in list) if (w.type.name == _resultType) w];
    int sites(WorkInfo w) => w.links.map((l) => l.sourceId).toSet().length;
    switch (_resultSort) {
      case _ResultSort.relevance:
        break;
      case _ResultSort.sources:
        list = [...list]..sort((a, b) => sites(b).compareTo(sites(a)));
      case _ResultSort.title:
        list = [...list]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  String _sort = 'TRENDING_DESC';
  String? _genre;
  String? _country;
  final List<WorkInfo> _catalog = [];
  int _catalogPage = 0;
  bool _catalogLoading = false;
  bool _catalogEnd = false;
  Object? _catalogError;
  int _catalogToken = 0;
  int _webShown = 60;

  // « Statut des séries » : every work by real status — the library
  // (status engine) and the whole AniList catalogue filtered by status
  // (RELEASING / HIATUS / CANCELLED / FINISHED), page after page.
  SeriesStatus _statusTab = SeriesStatus.ongoing;
  final Map<SeriesStatus, List<WorkInfo>> _statusCatalog = {};
  final Map<SeriesStatus, int> _statusPage = {};
  final Set<SeriesStatus> _statusEnd = {};
  bool _statusLoading = false;
  final Set<String> _loggedStatus = {};

  static const _aniListStatus = {
    SeriesStatus.ongoing: 'RELEASING',
    SeriesStatus.hiatus: 'HIATUS',
    SeriesStatus.cancelled: 'CANCELLED',
    SeriesStatus.completed: 'FINISHED',
  };

  Future<void> _loadStatusPage(SeriesStatus status) async {
    if (_statusLoading || _statusEnd.contains(status)) return;
    setState(() => _statusLoading = true);
    final page = (_statusPage[status] ?? 0) + 1;
    try {
      final works = await AppScope.read(context).anilist.comicCatalog(
          sort: 'POPULARITY_DESC', status: _aniListStatus[status], page: page, perPage: 40);
      if (!mounted) return;
      setState(() {
        _statusPage[status] = page;
        final list = _statusCatalog.putIfAbsent(status, () => []);
        final seen = {for (final w in list) w.id};
        list.addAll(works.where((w) => seen.add(w.id)));
        if (works.length < 40) _statusEnd.add(status);
      });
    } catch (e) {
      // AniList busy: the button stays, try again later.
      AppLog.info('Statut « ${status.label} » : AniList indisponible ($e)');
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  List<Widget> _statusSlivers(AppState app) {
    final p = context.pal;
    final mine = <SeriesStatus, List<WorkInfo>>{};
    final reasons = <String, String>{};
    for (final e in app.entries) {
      if (e.work.type == ContentType.anime) continue;
      final d = app.seriesStatus(e.work);
      final s = d.status == SeriesStatus.unknown ? SeriesStatus.ongoing : d.status;
      mine.putIfAbsent(s, () => []).add(e.work);
      reasons[e.work.id] = d.reason;
    }
    final shownMine = mine[_statusTab] ?? const <WorkInfo>[];
    // AniList's status checked by the engine (real recent chapters): a
    // series AniList still calls « hiatus » but released 5 days ago moves
    // to « En cours ».
    SeriesStatus real(WorkInfo w) {
      final s = app.seriesStatus(w).status;
      return s == SeriesStatus.unknown ? SeriesStatus.ongoing : s;
    }
    final loaded = _statusCatalog[_statusTab];
    if (loaded != null && _loggedStatus.add('${_statusTab.name}:${loaded.length}')) {
      // Why each AniList series was kept or moved (diagnosis in pazulu.log).
      final moved = [
        for (final w in loaded)
          if (real(w) != _statusTab) '${w.title} → ${app.seriesStatus(w).status.label} '
              '(${app.seriesStatus(w).reason}; AniList : ${w.publicationStatus})',
      ];
      AppLog.info('Statut « ${_statusTab.label} » : ${loaded.length} séries AniList, '
          '${loaded.length - moved.length} gardées, ${moved.length} déplacées'
          '${moved.isEmpty ? '' : ' : ${moved.take(15).join(' | ')}'}');
    }
    final catalog = loaded == null
        ? null
        : [
            for (final w in loaded) if (real(w) == _statusTab) w,
            if (_statusTab == SeriesStatus.ongoing)
              for (final e in _statusCatalog.entries)
                if (e.key != SeriesStatus.ongoing)
                  for (final w in e.value) if (real(w) == SeriesStatus.ongoing) w,
          ];
    final shownCatalog = catalog == null ? const <WorkInfo>[] : _visible(app, catalog);
    if (catalog == null && !_statusLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadStatusPage(_statusTab);
      });
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.md),
          child: Text('Statut décidé par AniList, MangaDex, MangaUpdates, chaque site et la date du '
              'dernier chapitre. Pause, annulées et terminées ne sont pas dans le planning.',
              style: TextStyle(color: p.muted, fontSize: 12.5)),
        ),
      ),
      if (shownMine.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, 4),
            child: Text('Dans ma bibliothèque (${shownMine.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        _grid(shownMine, 'status-mine-${_statusTab.name}'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.md),
            child: Text(
              [for (final w in shownMine.take(12)) '${w.title} : ${reasons[w.id]}'].join(' · '),
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, 4),
          child: Text('Toutes les lectures « ${_statusTab.label} » (${catalog?.length ?? 0}'
              '${_statusEnd.contains(_statusTab) ? '' : '+'})',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      if (catalog == null || catalog.isEmpty)
        (_statusLoading ? _skeleton() : const SliverToBoxAdapter(child: SizedBox(height: 8)))
      else
        SliverPadding(
          padding: const EdgeInsets.all(PazuluSpace.lg),
          sliver: SliverGrid.builder(
            gridDelegate: coverGridDelegate(app.settings.gridColumns),
            itemCount: shownCatalog.length,
            itemBuilder: (context, i) {
              final w = shownCatalog[i];
              return WorkCard(
                work: w,
                heroTag: 'st-${_statusTab.name}-${w.id}',
                subtitle: _catalogSubtitle(w),
                hoverInfo: workPreview(w, status: app.seriesStatus(w).status.label),
                onTap: () => _openCatalogWork(w),
              );
            },
          ),
        ),
      if (catalog != null && !_statusEnd.contains(_statusTab))
        SliverToBoxAdapter(child: Center(child: Padding(
          padding: const EdgeInsets.only(bottom: PazuluSpace.lg),
          child: _statusLoading
              ? const CircularProgressIndicator()
              : OutlinedButton.icon(
                  onPressed: () => _loadStatusPage(_statusTab),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('Voir plus', style: TextStyle(color: p.text)),
                ),
        ))),
    ];
  }

  // « Tous les titres » : the local index of every site's catalogue.
  final _indexFilter = TextEditingController();
  String _indexQuery = '';
  int _indexShown = 200;
  List<IndexedWork>? _indexCache;
  String? _indexCacheKey;

  List<IndexedWork> _indexWorks(AppState app) {
    final all = app.siteIndex.works;
    if (all == null) {
      // Sorted in background (hundreds of thousands of titles), then shown.
      app.siteIndex.prepareWorks().then((_) {
        if (mounted) setState(() {});
      });
      return const [];
    }
    final key = '${identityHashCode(all)}|$_indexQuery';
    if (_indexCache != null && _indexCacheKey == key) return _indexCache!;
    final q = SiteTitleIndex.norm(_indexQuery);
    _indexCacheKey = key;
    return _indexCache = q.isEmpty ? all : all.where((w) => w.key.contains(q)).toList();
  }

  List<Widget> _indexSlivers(AppState app) {
    final p = context.pal;
    final works = _indexWorks(app);
    final crawl = app.indexProgress;
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          app.siteIndex.works == null
              ? 'Tous les titres (préparation…)'
              : 'Tous les titres (${app.siteIndex.works!.length})',
          subtitle: 'Catalogues complets de ${app.siteIndex.siteCount} sites, '
              'chaque œuvre avec tous ses sites',
          trailing: crawl == null
              ? TextButton.icon(
                  onPressed: () => app.crawlSiteIndex(maxAge: const Duration(hours: 1)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Actualiser'),
                )
              : null,
        ),
      ),
      if (crawl != null) _progressBar(crawl, 'Lecture des catalogues des sites'),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TextField(
              controller: _indexFilter,
              onChanged: (v) => setState(() {
                _indexQuery = v;
                _indexShown = 200;
              }),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list_rounded),
                hintText: 'Filtrer les titres…',
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      if (works.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg, vertical: 8),
            child: Text(
              app.siteIndex.siteCount == 0
                  ? 'Les catalogues des sites se chargent au démarrage.'
                  : 'Aucun titre ne correspond.',
              style: TextStyle(color: p.muted)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
          sliver: SliverList.builder(
            itemCount: works.length < _indexShown ? works.length : _indexShown,
            itemBuilder: (context, i) {
              final w = works[i];
              final names = [for (final l in w.links.take(3)) app.sourceName(l.sourceId)];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => pushPage(context,
                        WorkPage(work: w.toWork(), heroTag: 'idx-${w.key}')),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(names.join(' · ') +
                                  (w.links.length > 3 ? ' · +${w.links.length - 3}' : ''),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12)),
                        ])),
                        const SizedBox(width: 10),
                        Tag('${w.links.length} site${w.links.length > 1 ? 's' : ''}'),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      if (works.length > _indexShown)
        SliverToBoxAdapter(child: Center(child: Padding(
          padding: const EdgeInsets.only(bottom: PazuluSpace.lg),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _indexShown += 400),
            icon: const Icon(Icons.expand_more_rounded),
            label: Text('Voir plus (${works.length - _indexShown} autres)'),
          ),
        ))),
    ];
  }

  // Merge of the connectors' list and every site's list, recomputed only
  // when one of them changes (never at every frame).
  List<WorkInfo>? _mergedCache;
  Object? _mergedPopular;
  Object? _mergedBrowsed;

  List<WorkInfo> _allWorks(List<WorkInfo> browsed) {
    if (_mergedCache != null && identical(_mergedPopular, _popular) &&
        identical(_mergedBrowsed, browsed)) {
      return _mergedCache!;
    }
    _mergedPopular = _popular;
    _mergedBrowsed = browsed;
    // Alternate the two lists so the top of the grid mixes every source.
    final mixed = <WorkInfo>[];
    final n = _popular.length > browsed.length ? _popular.length : browsed.length;
    for (var i = 0; i < n; i++) {
      if (i < _popular.length) mixed.add(_popular[i]);
      if (i < browsed.length) mixed.add(browsed[i]);
    }
    return _mergedCache = mergeSearchResults(mixed);
  }

  Future<void> _loadCatalog({bool reset = false}) async {
    if (_catalogLoading && !reset) return;
    final token = reset ? ++_catalogToken : _catalogToken;
    if (reset) {
      _catalog.clear();
      _catalogPage = 0;
      _catalogEnd = false;
    }
    setState(() { _catalogLoading = true; _catalogError = null; });
    try {
      final page = await AppScope.read(context).anilist.comicCatalog(
          sort: _sort, genre: _genre, country: _country, page: _catalogPage + 1);
      if (!mounted || token != _catalogToken) return;
      setState(() {
        _catalogPage++;
        _catalog.addAll(page);
        _catalogEnd = page.length < 40;
      });
    } catch (e) {
      if (mounted && token == _catalogToken) setState(() => _catalogError = e);
    } finally {
      if (mounted && token == _catalogToken) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _openCatalogWork(WorkInfo meta) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    var closed = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text('Recherche des lecteurs de « ${meta.title} »…')),
        ]),
      ),
    ).then((_) => closed = true);
    WorkInfo work;
    try {
      work = await app.resolveCatalogWork(meta).timeout(const Duration(seconds: 15));
    } catch (_) {
      work = meta;
    }
    if (!mounted) return;
    if (!closed) navigator.pop();
    pushPage(context, WorkPage(work: work, heroTag: 'cat-${meta.id}'));
  }

  static String _catalogSubtitle(WorkInfo w) => [
        w.type.label,
        ...w.tags.where((t) => t.startsWith('★')).take(1),
        if (w.lastChapter != null) '${w.lastChapter} ch.'
        else if (w.publicationStatus != null) w.publicationStatus!,
      ].join(' · ');

  List<Widget> _catalogSlivers() {
    final p = context.pal;
    final app = AppScope.of(context);
    final shownCatalog = _visible(app, _catalog);
    return [
      SliverToBoxAdapter(child: SectionHeader(_sorts[_sort] ?? 'Catalogue',
          subtitle: 'Les lecteurs sont cherchés sur toutes les sources à l\'ouverture')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ALL', label: Text('Tous')),
                  ButtonSegment(value: 'JP', label: Text('Manga')),
                  ButtonSegment(value: 'KR', label: Text('Manhwa')),
                  ButtonSegment(value: 'CN', label: Text('Manhua')),
                ],
                selected: {_country ?? 'ALL'},
                onSelectionChanged: (v) {
                  setState(() => _country = v.first == 'ALL' ? null : v.first);
                  _loadCatalog(reset: true);
                },
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final g in [null, ..._genres])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(g == null ? Icons.apps_rounded : _genreIcons[g] ?? Icons.label_rounded,
                          size: 16),
                      label: Text(g == null ? 'Tous les genres' : _genreFr[g] ?? g),
                      selected: _genre == g,
                      onSelected: (_) {
                        setState(() => _genre = g);
                        _loadCatalog(reset: true);
                      },
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      if (_catalog.isEmpty && _catalogLoading)
        _skeleton()
      else if (_catalog.isEmpty && _catalogError != null)
        SliverToBoxAdapter(child: ErrorState(error: _catalogError!,
            onRetry: () => _loadCatalog(reset: true)))
      else
        SliverPadding(
          padding: const EdgeInsets.all(PazuluSpace.lg),
          sliver: SliverGrid.builder(
            gridDelegate: coverGridDelegate(app.settings.gridColumns),
            itemCount: shownCatalog.length,
            itemBuilder: (context, i) {
              final w = shownCatalog[i];
              return WorkCard(
                work: w,
                heroTag: 'cat-${w.id}',
                subtitle: _catalogSubtitle(w),
                hoverInfo: workPreview(w, status: app.seriesStatus(w).status == SeriesStatus.unknown
                    ? w.publicationStatus : app.seriesStatus(w).status.label),
                badge: app.entries.any((e) => sameWorkAcrossSources(e.work,
                    WorkInfo(id: w.id, title: w.title, altTitles: w.altTitles, type: w.type)))
                    ? 'Suivi' : null,
                onTap: () => _openCatalogWork(w),
              );
            },
          ),
        ),
      if (_catalog.isNotEmpty && !_catalogEnd)
        SliverToBoxAdapter(child: Center(child: Padding(
          padding: const EdgeInsets.only(bottom: PazuluSpace.lg),
          child: _catalogLoading
              ? const CircularProgressIndicator()
              : OutlinedButton.icon(
                  onPressed: _loadCatalog,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('Voir plus', style: TextStyle(color: p.text)),
                ),
        ))),
    ];
  }

  // Anime (AniList metadata; watching happens on official platforms).
  List<AnimeInfo> _trending = const [];
  List<FreshEpisode> _fresh = const [];
  bool _freshLoading = false;
  Object? _freshError;
  bool _trendingLoading = false;
  Object? _trendingError;
  List<AnimeInfo> _animeResults = const [];
  String _animeQuery = '';
  bool _animeSearching = false;
  Object? _animeError;
  String _lastQuery = '';
  int _generation = 0;
  bool _started = false;

  List<WorkInfo> _popular = const [];
  bool _popularLoading = true;
  Object? _popularError;

  List<WorkInfo> _results = const [];
  SearchProgress _progress = const SearchProgress();
  bool _searching = false;
  Object? _searchError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.read(context);
    app.search('').then((value) {
      if (mounted) setState(() { _popular = value; _popularLoading = false; });
    }, onError: (Object e) {
      if (mounted) setState(() { _popularError = e; _popularLoading = false; });
    });
    // Works of every site of the directory (home pages), progressively.
    app.browseEverywhere();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCatalog(reset: true);
    });
  }

  @override
  void dispose() {
    discoverSearchRequest.removeListener(_onExternalSearch);
    _scroll.dispose();
    _searchFocus.dispose();
    _controller.dispose();
    _indexFilter.dispose();
    super.dispose();
  }

  Future<void> _createManualWork(BuildContext context) async {
    final app = AppScope.read(context);
    final controller = TextEditingController();
    var type = ContentType.manhwa;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Ajouter une œuvre manuellement'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Titre de l’œuvre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ContentType>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: [
                    for (final t in ContentType.values.where((e) => e != ContentType.anime))
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) type = value;
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  refresh(() => error = 'Indique un titre.');
                  return;
                }
                final work = app.createManualWork(controller.text, type);
                Navigator.pop(dialogContext);
                pushPage(context, WorkPage(work: work, heroTag: 'manual-${work.id}'));
              },
              child: const Text('Créer la fiche'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    if (mode == _Mode.anime && _trending.isEmpty && !_trendingLoading) _loadTrending();
    if (mode == _Mode.anime && _fresh.isEmpty && !_freshLoading) _loadFresh();
  }

  /// Episodes released on Crunchyroll in the last 3 days (AniList times).
  Future<void> _loadFresh() async {
    setState(() { _freshLoading = true; _freshError = null; });
    try {
      final app = AppScope.read(context);
      final now = DateTime.now();
      final frFuture = app.loadFrPlanning();
      // Japanese airings up to 4 days back: the French release can come a
      // day later.
      final airings = await app.anilist
          .airingBetween(now.subtract(const Duration(days: 4)), now, maxPages: 8);
      final fr = await frFuture;
      if (mounted) setState(() => _fresh = Crunchyroll.fresh(airings, now: now, fr: fr));
    } catch (e) {
      if (mounted) setState(() => _freshError = e);
    } finally {
      if (mounted) setState(() => _freshLoading = false);
    }
  }

  Widget _freshGrid() {
    final app = AppScope.of(context);
    return SliverPadding(
      padding: const EdgeInsets.all(PazuluSpace.lg),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate(app.settings.gridColumns),
        itemCount: _fresh.length,
        itemBuilder: (context, i) {
          final f = _fresh[i];
          final work = f.info.toWork();
          final url = f.url;
          return FadeSlideIn(
            key: ValueKey('cr-${f.info.id}-${f.episode}'),
            index: i < 24 ? i : 24,
            child: WorkCard(
              work: work,
              heroTag: 'cr-${f.info.id}-${f.episode}',
              subtitle: 'Ép. ${f.episode} · ${f.french ? 'en France' : 'au Japon'} ${relativeTime(f.airedAt)}',
              badge: app.inLibrary(work.id) ? 'Suivi' : 'Nouveau',
              hoverInfo: f.french
                  ? 'Épisode ${f.episode} sur Crunchyroll France vers ${clockTime(f.airedAt)} '
                      '(${shortDate(f.airedAt)}) · Japon ${clockTime(f.jpAt)}'
                  : 'Épisode ${f.episode} diffusé au Japon ${shortDate(f.jpAt)} à ${clockTime(f.jpAt)} '
                      '(heure France inconnue)',
              corner: url == null ? null : CrunchyrollButtons(url: url, title: f.info.title, episode: f.episode, compact: true,
                  hints: Crunchyroll.seasonHints(f.info)),
              onTap: () => pushPage(context, AnimePage(work: work, info: f.info,
                  heroTag: 'cr-${f.info.id}-${f.episode}')),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadTrending() async {
    setState(() { _trendingLoading = true; _trendingError = null; });
    try {
      final list = await AppScope.read(context).anilist.trending();
      if (mounted) setState(() => _trending = list);
    } catch (e) {
      if (mounted) setState(() => _trendingError = e);
    } finally {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _searchAnime(String q) async {
    final query = q.trim();
    final generation = ++_generation;
    setState(() {
      _animeQuery = query;
      _animeResults = const [];
      _animeError = null;
      _animeSearching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    try {
      final list = await AppScope.read(context).anilist.search(query);
      if (mounted && generation == _generation) setState(() => _animeResults = list);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _animeError = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _animeSearching = false);
    }
  }

  void _submit(String q) {
    if (_mode == _Mode.anime) {
      _searchAnime(q);
      return;
    }
    // The index answers at once (every site's catalogue), the live search
    // of all sources follows.
    AppScope.read(context).addRecentSearch(q);
    _searchFocus.unfocus();
    setState(() {
      _typing = q;
      _indexFilter.text = q;
      _indexQuery = q;
      _indexShown = 200;
    });
    _search(q);
  }

  Widget _animeGrid(List<AnimeInfo> list, String prefix) {
    final app = AppScope.of(context);
    return SliverPadding(
      padding: const EdgeInsets.all(PazuluSpace.lg),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate(app.settings.gridColumns),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final info = list[i];
          final work = info.toWork();
          final next = info.nextAiring;
          final subtitle = next != null
              ? 'Ép. ${next.episode} · ${countdown(next.airingAt)}'
              : [info.statusLabel, if (info.seasonLabel != null) info.seasonLabel!].join(' · ');
          return FadeSlideIn(
            key: ValueKey('$prefix-$_generation-${info.id}'),
            index: i < 24 ? i : 24,
            child: WorkCard(
              work: work,
              heroTag: '$prefix-${info.id}',
              subtitle: subtitle,
              badge: app.inLibrary(work.id) ? 'Suivi' : null,
              onTap: () => pushPage(context, AnimePage(work: work, info: info,
                  heroTag: '$prefix-${info.id}')),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _animeSlivers() {
    final p = context.pal;
    if (_animeQuery.isNotEmpty) {
      return [
        SliverToBoxAdapter(child: SectionHeader('Animés pour « $_animeQuery »')),
        if (_animeSearching)
          _skeleton()
        else if (_animeError != null)
          SliverToBoxAdapter(child: ErrorState(error: _animeError!, onRetry: () => _searchAnime(_animeQuery)))
        else if (_animeResults.isEmpty)
          const SliverToBoxAdapter(child: EmptyState(
            icon: Icons.search_off_rounded, title: 'Aucun animé trouvé',
            message: 'Essayez le titre japonais en romaji ou le titre anglais.'))
        else
          _animeGrid(_animeResults, 'ani-res'),
      ];
    }
    return [
      SliverToBoxAdapter(child: SectionHeader('Sortis récemment sur Crunchyroll',
          subtitle: 'Épisodes des 3 derniers jours · heure de sortie en France · '
              'lecture sur ton compte Crunchyroll',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: () => joinPartyDialog(context),
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: const Text('Rejoindre une soirée'),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _freshLoading ? null : _loadFresh,
              icon: Icon(Icons.refresh_rounded, color: p.muted),
            ),
          ]))),
      if (_freshLoading && _fresh.isEmpty)
        _skeleton()
      else if (_freshError != null && _fresh.isEmpty)
        SliverToBoxAdapter(child: ErrorState(error: _freshError!, onRetry: _loadFresh))
      else if (_fresh.isEmpty)
        const SliverToBoxAdapter(child: EmptyState(
            icon: Icons.live_tv_rounded, title: 'Rien de neuf sur Crunchyroll',
            message: 'Aucun épisode diffusé ces 3 derniers jours n’est référencé sur Crunchyroll.'))
      else
        _freshGrid(),
      SliverToBoxAdapter(child: SectionHeader('Tendances de la saison',
          subtitle: 'Données AniList · regardez sur les plateformes officielles',
          trailing: IconButton(
            tooltip: 'Actualiser',
            onPressed: _trendingLoading ? null : _loadTrending,
            icon: Icon(Icons.refresh_rounded, color: p.muted),
          ))),
      if (_trendingLoading && _trending.isEmpty)
        _skeleton()
      else if (_trendingError != null && _trending.isEmpty)
        SliverToBoxAdapter(child: ErrorState(error: _trendingError!, onRetry: _loadTrending))
      else
        _animeGrid(_trending, 'ani-top'),
    ];
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    final generation = ++_generation;
    setState(() {
      _lastQuery = query;
      _results = const [];
      _searchError = null;
      _searching = query.isNotEmpty;
      _progress = const SearchProgress();
    });
    if (query.isEmpty) return;
    try {
      final all = await AppScope.read(context).searchEverywhere(query,
          onUpdate: (results, progress) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _results = results;
          _progress = progress;
        });
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = all;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  Widget _grid(List<WorkInfo> all, String prefix) {
    final app = AppScope.of(context);
    final works = _visible(app, all);
    return SliverPadding(
      padding: const EdgeInsets.all(PazuluSpace.lg),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate(app.settings.gridColumns),
        itemCount: works.length,
        itemBuilder: (context, i) {
          final w = works[i];
          final sites = w.links.map((l) => l.sourceId).toSet().length;
          return FadeSlideIn(
            key: ValueKey('$prefix-$_generation-${w.id}'),
            index: i < 24 ? i : 24,
            child: WorkCard(
              work: w,
              heroTag: '$prefix-${w.id}',
              subtitle: sites > 1 ? '${workSubtitle(w)} · $sites sources' : workSubtitle(w),
              badge: app.inLibrary(w.id) ? 'Suivi' : null,
              hoverInfo: workPreview(w, sites: sites),
              corner: app.entry(w.id) == null
                  ? _QuickAdd(work: w)
                  : EntryMenuButton(entry: app.entry(w.id)!),
              onTap: () => pushPage(context, WorkPage(work: w, heroTag: '$prefix-${w.id}')),
            ),
          );
        },
      ),
    );
  }

  Widget _skeleton() {
    final app = AppScope.of(context);
    return SliverPadding(
      padding: const EdgeInsets.all(PazuluSpace.lg),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate(app.settings.gridColumns),
        itemCount: 12,
        itemBuilder: (_, __) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 2 / 3, child: Pulse()),
            SizedBox(height: 8),
            Pulse(height: 14, width: 110, radius: 6),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(SearchProgress p, String label) {
    final pal = context.pal;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label : ${p.done}/${p.total} sources interrogées · '
                '${p.found} fiche(s)${p.failed > 0 ? ' · ${p.failed} injoignable(s)' : ''}',
                style: TextStyle(color: pal.muted, fontSize: 12)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: p.total == 0 ? null : p.ratio, minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final webCount = app.webConnectors().length;
    final browsed = app.browsedWorks;
    final allWorks = _allWorks(browsed);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: ScrollToTopButton(controller: _scroll),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const PageTitle('Découvrir', kicker: 'Tous les sites, tous les titres', size: 40),
                      const Spacer(),
                      SegmentedButton<_Mode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _Mode.reads, icon: Icon(Icons.menu_book_rounded),
                              label: Text('Lectures')),
                          ButtonSegment(value: _Mode.anime, icon: Icon(Icons.live_tv_rounded),
                              label: Text('Animés')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) => _setMode(v.first),
                      ),
                    ]),
                    const SizedBox(height: PazuluSpace.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: TextField(
                        controller: _controller,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _submit,
                        onChanged: (v) => setState(() => _typing = v),
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          prefixIcon: _typing.isEmpty ? const Icon(Icons.search) : IconButton(
                            tooltip: 'Effacer la recherche',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _typing = '');
                              _search('');
                            },
                          ),
                          hintText: _mode == _Mode.anime
                              ? 'Titre de l\'animé (romaji, anglais, français)…'
                              : 'Titre, titre alternatif, auteur…',
                          contentPadding: const EdgeInsets.symmetric(vertical: 18),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(6),
                            child: GlowButton(label: 'Chercher', onPressed: () => _submit(_controller.text)),
                          ),
                        ),
                      ),
                    ),
                    if (_mode == _Mode.reads) _suggestions(app),
                    const SizedBox(height: PazuluSpace.md),
                    if (_mode == _Mode.reads) Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Every source at the same level: one count, no « main » source.
                        Tag('${app.nativeReaderCount + webCount} sources interrogées à chaque recherche',
                          color: p.bright, icon: Icons.travel_explore_rounded),
                        TextButton.icon(
                          onPressed: () => pushPage(context, const SourcesPage()),
                          icon: const Icon(Icons.language_rounded, size: 18),
                          label: const Text('Gérer mes sources'),
                        ),
                        TextButton.icon(
                          onPressed: () => _createManualWork(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Créer une fiche'),
                        ),
                        FilterChip(
                          avatar: const Icon(Icons.visibility_off_outlined, size: 16),
                          label: const Text('Masquer ma bibliothèque'),
                          selected: _hideMine,
                          onSelected: (v) => setState(() => _hideMine = v),
                        ),
                        Text(
                          'Langues : ${app.settings.comicLangs.map((l) => l.toUpperCase()).join(', ')}',
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_mode == _Mode.anime) ..._animeSlivers()
            else if (_lastQuery.isNotEmpty) ...[
              SliverToBoxAdapter(child: SectionHeader('Résultats pour « $_lastQuery »',
                  subtitle: _results.isEmpty ? null : '${_sortedResults(app).length} œuvre(s)')),
              if (_results.isNotEmpty) SliverToBoxAdapter(child: _resultFilters()),
              if (_searching) _progressBar(_progress, 'Recherche sur toutes les sources'),
              if (_searchError != null && _results.isEmpty)
                SliverToBoxAdapter(
                  child: ErrorState(error: _searchError!, onRetry: () => _search(_lastQuery)),
                )
              else if (_results.isEmpty && _searching)
                _skeleton()
              else if (_results.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Aucun résultat',
                    message: 'Essayez le titre anglais, français ou le titre original en romaji.',
                  ),
                )
              else
                _grid(_sortedResults(app), 'res'),
              if (!_searching && app.publicSearchStatus.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg, vertical: 6),
                    child: ExpansionTile(
                      title: Text('Rapport des ${app.publicSearchStatus.length} sites interrogés',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                      children: [
                        for (final status in app.publicSearchStatus.entries)
                          ListTile(
                            dense: true,
                            title: Text(app.siteById(status.key)?.title ?? status.key),
                            subtitle: Text(status.value),
                          ),
                      ],
                    ),
                  ),
                ),
              ..._indexSlivers(app),
            ] else ...[
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: PazuluSpace.md),
                child: _sectionTiles(),
              )),
              if (_sections[_section]!.sort != null) ..._catalogSlivers()
              else if (_sections[_section]!.status != null) ..._statusSlivers(app)
              else if (_section == _Section.titles) ..._indexSlivers(app)
              else ...[
              // ONE list for every source (integrated connectors and the
              // 200+ sites at the same level), duplicates merged.
              SliverToBoxAdapter(
                child: SectionHeader(
                  'Toutes les sources (${allWorks.length} œuvres)',
                  subtitle: 'Connecteurs et sites mélangés, doublons fusionnés',
                  trailing: TextButton.icon(
                    onPressed: app.browsing ? null : () => app.browseEverywhere(force: true),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Actualiser'),
                  ),
                ),
              ),
              if (app.browsing) _progressBar(app.browseProgress, 'Chargement des catalogues'),
              if (allWorks.isEmpty && (app.browsing || _popularLoading))
                _skeleton()
              else if (allWorks.isEmpty && _popularError != null)
                SliverToBoxAdapter(child: ErrorState(error: _popularError!,
                    onRetry: () => app.browseEverywhere(force: true)))
              else if (allWorks.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.public_off_rounded,
                    title: 'Aucun catalogue chargé',
                    message: 'Aucun site n\'a répondu. Vérifiez la connexion puis « Actualiser ».',
                  ),
                )
              else ...[
                _grid(allWorks.take(_webShown).toList(), 'web'),
                if (allWorks.length > _webShown)
                  SliverToBoxAdapter(child: Center(child: Padding(
                    padding: const EdgeInsets.only(bottom: PazuluSpace.lg),
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _webShown += 60),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text('Voir plus (${allWorks.length - _webShown} autres)'),
                    ),
                  ))),
              ],
              ],
            ],
            if (_mode == _Mode.reads) SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.xl),
                child: Text(
                  'Chaque recherche interroge toutes les sources, dix à la fois. Les sites qui '
                  'bloquent les robots, exigent une connexion ou un abonnement sont signalés '
                  'dans le rapport, jamais contournés. Les pages ne sont téléchargées qu\'à la lecture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _CategoryTile extends StatefulWidget {
  const _CategoryTile({required this.info, required this.selected, required this.onTap, required this.fill});

  final _SectionInfo info;
  final Color fill;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sel = widget.selected;
    final info = widget.info;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PazuluMotion.of(context, PazuluMotion.hover),
          width: 172,
          padding: const EdgeInsets.all(12),
          transform: Matrix4.translationValues(_hover || sel ? -2 : 0, _hover || sel ? -2 : 0, 0)
            ..rotateZ(sel ? -0.02 : 0),
          decoration: BoxDecoration(
            color: widget.fill,
            border: Border.all(color: const Color(0xFF111111), width: sel ? 3.5 : 2.5),
            boxShadow: [BoxShadow(color: p.ink, offset: Offset(_hover || sel ? 6 : 4, _hover || sel ? 6 : 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(info.icon, color: const Color(0xFF111111), size: 26),
            const Spacer(),
            Text(info.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: kiosqueDisplay(15, color: const Color(0xFF111111))),
            const SizedBox(height: 2),
            Text(info.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF111111), fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Fonds des tuiles de catégories (vifs, texte encre lisible).
const _tileFills = <Color>[
  Color(0xFFFFD400), Color(0xFFFF6FB0), Color(0xFF2CC8E8), Color(0xFF3DDC84), Color(0xFFFF9A1F),
  Color(0xFFC9C6BD), Color(0xFFFF4A3D), Color(0xFFB9A6FF), Color(0xFF9BE15D), Color(0xFFF2F1EC),
];

/// « + » on a cover: added to the library without opening the page.
class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.work});

  final WorkInfo work;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ajouter à la bibliothèque',
      child: Material(
        color: context.pal.accent,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF111111), width: 2)),
        child: InkWell(
          onTap: () {
            final app = AppScope.read(context);
            app.addToLibrary(work);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('« ${work.title} » ajouté à la bibliothèque (À lire)'),
              action: SnackBarAction(label: 'Annuler', onPressed: () => app.removeFromLibrary(work.id)),
            ));
          },
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.add_rounded, size: 18, color: Color(0xFF111111)),
          ),
        ),
      ),
    );
  }
}
