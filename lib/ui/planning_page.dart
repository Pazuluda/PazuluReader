import 'dart:async';

import 'package:flutter/material.dart';


import '../core/work_status.dart';
import '../core/models.dart';
import '../core/planning.dart';
import '../core/schedule/weekly_schedule.dart';
import '../design/theme.dart';
import 'anime_page.dart';
import 'app_scope.dart';
import 'external_link.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'work_page.dart';

/// Planning : la semaine de TOUTES les sorties (animés, chapitres EN et FR)
/// jour par jour et heure par heure, filtrable sur « Ma liste » ; et le
/// planning personnel de lecture.
class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

enum _Tab { week, reading }

enum _Kind { all, reads, anime }

class _PlanningPageState extends State<PlanningPage> {
  _Tab _tab = _Tab.week;
  _Kind _kind = _Kind.all;
  final Set<String> _langs = {'en', 'fr', 'ja'};
  // « Ma liste » first: the series I follow, the whole week one click away.
  bool _mine = true;
  String _query = '';
  final _search = TextEditingController();
  late DateTime _weekStart = WeeklyScheduleBuilder.weekStart(DateTime.now());
  late int _day = DateTime.now().weekday;
  bool _started = false;
  Timer? _searchDebounce;
  final Set<String> _expandedHours = {};

  static const _days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _longDays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      app.refreshAnimePlanning();
      app.schedule.load(_weekStart);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _moveWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      final thisWeek = WeeklyScheduleBuilder.weekStart(DateTime.now());
      _day = _weekStart == thisWeek ? DateTime.now().weekday : 1;
    });
    AppScope.read(context).schedule.load(_weekStart);
  }

  Future<void> _refresh() async {
    final app = AppScope.read(context);
    app.resumePausedSources();
    await Future.wait([
      app.schedule.load(_weekStart, force: true),
      app.refreshAnimePlanning(force: true),
    ]);
  }

  bool _keep(ScheduleSlot s, List<LibraryEntry> entries) {
    if (_kind == _Kind.reads && s.kind != SlotKind.comic) return false;
    if (_kind == _Kind.anime && s.kind != SlotKind.anime) return false;
    if (s.kind == SlotKind.comic && !_langs.contains(s.lang)) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      if (!s.title.toLowerCase().contains(q) &&
          !s.altTitles.any((t) => t.toLowerCase().contains(q))) {
        return false;
      }
    }
    if (_mine && !WeeklyScheduleBuilder.followed(s, entries)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = AppScope.of(context);
    final entries = app.entries.toList();
    final all = app.schedule.week(_weekStart) ?? const <ScheduleSlot>[];
    // Paused / cancelled / finished series of the library: not planned.
    final inactive = [
      for (final e in entries) if (!app.seriesStatus(e.work).status.active) e,
    ];
    final visible = _tab == _Tab.week
        ? [
            for (final s in all)
              if (_keep(s, entries) &&
                  (s.state != SlotState.estimated ||
                      !WeeklyScheduleBuilder.followed(s, inactive)))
                s,
          ]
        : const <ScheduleSlot>[];
    final perDay = List<int>.filled(7, 0);
    for (final s in visible) {
      final d = s.at.toLocal().difference(_weekStart).inDays;
      if (d >= 0 && d < 7) perDay[d]++;
    }
    final dayStart = _weekStart.add(Duration(days: _day - 1));
    final dayEnd = dayStart.add(const Duration(days: 1));
    final todays = [
      for (final s in visible)
        if (!s.at.toLocal().isBefore(dayStart) && s.at.toLocal().isBefore(dayEnd)) s,
    ]..sort((a, b) {
        // Known hours first in time order, then the « during the day » ones.
        if (a.timeKnown != b.timeKnown) return a.timeKnown ? -1 : 1;
        return a.at.compareTo(b.at);
      });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 0),
                  sliver: SliverList.list(children: [
                    Row(children: [
                      const Expanded(child: PageTitle('Au programme', kicker: 'Planning des sorties', size: 40)),
                      if (_tab == _Tab.week)
                        TextButton.icon(
                          onPressed: app.schedule.loading ? null : _refresh,
                          icon: app.schedule.loading
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded),
                          label: const Text('Actualiser'),
                        ),
                    ]),
                    const SizedBox(height: PazuluSpace.md),
                    SegmentedButton<_Tab>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: _Tab.week, icon: Icon(Icons.calendar_view_week_rounded),
                            label: Text('Semaine des sorties')),
                        ButtonSegment(value: _Tab.reading, icon: Icon(Icons.menu_book_rounded),
                            label: Text('Mes lectures')),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                    const SizedBox(height: PazuluSpace.md),
                    if (_tab == _Tab.week) ..._weekHeader(context, perDay, all.isEmpty),
                    if (_tab == _Tab.reading) ..._reading(context),
                  ]),
                ),
                if (_tab == _Tab.week) ...[
                  if (all.isEmpty && app.schedule.loading)
                    SliverToBoxAdapter(child: _loadingCard(context))
                  else if (todays.isEmpty)
                    SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
                      child: Glass(child: Text(
                        all.isEmpty
                            ? 'Planning pas encore chargé. Cliquez « Actualiser ».'
                            : (_mine
                                ? 'Aucune de vos séries ne sort ce jour-là.'
                                : 'Rien ce jour-là avec ces filtres.'),
                        style: TextStyle(color: p.muted))),
                    ))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
                      sliver: _timeline(context, todays, entries, dayStart),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.md, PazuluSpace.lg, PazuluSpace.xl),
                    sliver: SliverList.list(children: [
                      if (_mine) ..._statusSection(context),
                      _reportCard(context),
                      const SizedBox(height: 8),
                      Text(
                        'Animés : horaires officiels AniList (diffusion japonaise, en heure locale) '
                        'et plateformes de simulcast. Lectures : sorties réellement vues sur MangaDex, '
                        'WEBTOON et les sites du répertoire ; « Estimé » = calculé d\'après le rythme '
                        'réel de chaque série. Plus Pazulu observe, plus le planning se remplit.',
                        style: TextStyle(color: p.muted, fontSize: 12),
                      ),
                    ]),
                  ),
                ] else
                  const SliverToBoxAdapter(child: SizedBox(height: PazuluSpace.xl)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _weekHeader(BuildContext context, List<int> perDay, bool empty) {
    final p = context.pal;
    final end = _weekStart.add(const Duration(days: 6));
    final today = DateTime.now();
    return [
      Row(children: [
        IconButton.outlined(
          tooltip: 'Semaine précédente',
          onPressed: () => _moveWeek(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text('Semaine du ${_weekStart.day} ${shortDate(_weekStart).split(' ').last} '
              'au ${end.day} ${shortDate(end).split(' ').last}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        IconButton.outlined(
          tooltip: 'Semaine suivante',
          onPressed: () => _moveWeek(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: 74,
        child: Row(children: [
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Builder(builder: (context) {
                  final date = _weekStart.add(Duration(days: d - 1));
                  final isToday = date.year == today.year && date.month == today.month &&
                      date.day == today.day;
                  final selected = d == _day;
                  return Material(
                    color: selected ? p.selected : p.card,
                    borderRadius: BorderRadius.circular(PazuluRadius.card),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(PazuluRadius.card),
                      onTap: () => setState(() { _day = d; _expandedHours.clear(); }),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(PazuluRadius.card),
                          border: Border.all(color: isToday ? p.bright : p.border,
                              width: isToday ? 1.5 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${_days[d - 1]} ${date.day}', style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13,
                              color: selected || isToday ? p.bright : p.text)),
                          const SizedBox(height: 2),
                          Text('${perDay[d - 1]}', style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.public_rounded), label: Text('Tout le monde')),
            ButtonSegment(value: true, icon: Icon(Icons.bookmark_rounded), label: Text('Ma liste')),
          ],
          selected: {_mine},
          onSelectionChanged: (v) => setState(() => _mine = v.first),
        ),
        SegmentedButton<_Kind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Kind.all, label: Text('Tout')),
            ButtonSegment(value: _Kind.reads, icon: Icon(Icons.menu_book_rounded), label: Text('Lectures')),
            ButtonSegment(value: _Kind.anime, icon: Icon(Icons.live_tv_rounded), label: Text('Animés')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        if (_kind != _Kind.anime)
          for (final l in const ['en', 'fr'])
            FilterChip(
              label: Text(l.toUpperCase()),
              selected: _langs.contains(l),
              onSelected: (v) => setState(() => v ? _langs.add(l) : _langs.remove(l)),
            ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'Chercher une série dans le planning…',
          suffixIcon: _query.isEmpty ? null : IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _search.clear();
              setState(() => _query = '');
            },
          ),
        ),
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 250),
              () { if (mounted) setState(() => _query = v.trim()); });
        },
      ),
      const SizedBox(height: 4),
      if (_query.isNotEmpty) _searchWeekSummary(context),
      SectionHeader('${_longDays[_day - 1]} ${_weekStart.add(Duration(days: _day - 1)).day}',
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 8)),
    ];
  }

  /// When searching, where the series appears during the whole week.
  Widget _searchWeekSummary(BuildContext context) {
    final p = context.pal;
    final app = AppScope.read(context);
    final entries = app.entries.toList();
    final all = app.schedule.week(_weekStart) ?? const <ScheduleSlot>[];
    final hits = [for (final s in all) if (_keep(s, entries)) s];
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('« $_query » n\'apparaît pas cette semaine.', style: TextStyle(color: p.muted)),
      );
    }
    final days = <int>{for (final s in hits) s.at.toLocal().weekday}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final d in days)
          ActionChip(
            label: Text('${_days[d - 1]} · ${hits.where((s) => s.at.toLocal().weekday == d).length}'),
            onPressed: () => setState(() { _day = d; _expandedHours.clear(); }),
          ),
      ]),
    );
  }

  Widget _loadingCard(BuildContext context) {
    final p = context.pal;
    final s = AppScope.of(context).schedule;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg),
      child: Glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Construction du planning : AniList, MangaDex, WEBTOON et ${s.progressTotal - 4} sites…',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: s.progressTotal == 0 ? null : s.progressDone / s.progressTotal),
        const SizedBox(height: 6),
        Text('Une seule fois : ensuite le planning s\'affiche immédiatement et se met à jour tout seul.',
            style: TextStyle(color: p.muted, fontSize: 12)),
      ])),
    );
  }

  Widget _reportCard(BuildContext context) {
    final p = context.pal;
    final s = AppScope.of(context).schedule;
    final reports = s.reports;
    if (reports.isEmpty) return const SizedBox.shrink();
    final ok = reports.where((r) => r.ok).length;
    final built = s.builtAt(_weekStart);
    return Glass(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        title: Text('Sources du planning · $ok/${reports.length} ont répondu',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (built != null) 'mis à jour ${relativeTime(built)}',
          '${s.knownSeries} séries suivies par le rythme',
        ].join(' · '), style: TextStyle(color: p.muted, fontSize: 12)),
        children: [
          for (final r in [...reports]..sort((a, b) =>
              a.group == b.group ? b.count.compareTo(a.count) : a.group.compareTo(b.group)))
            ListTile(
              dense: true,
              leading: Icon(r.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 18, color: r.ok ? p.success : p.warning),
              title: Text(r.name),
              subtitle: Text(r.ok ? '${r.count} sortie(s) cette semaine' : r.error!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(r.group, style: TextStyle(color: p.muted, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  void _openSlot(ScheduleSlot s) {
    final app = AppScope.read(context);
    final heroTag = 'week-${s.mergeKey}';
    if (s.kind == SlotKind.anime) {
      final work = s.work ?? s.anime?.toWork();
      if (work == null) return;
      pushPage(context, AnimePage(work: work, info: s.anime, heroTag: heroTag));
      return;
    }
    for (final e in app.entries) {
      if (WeeklyScheduleBuilder.followed(s, [e])) {
        pushPage(context, WorkPage(work: e.work, heroTag: heroTag));
        return;
      }
    }
    final work = s.work;
    if (work != null) {
      pushPage(context, WorkPage(work: work, heroTag: heroTag));
    } else if (s.url != null) {
      openOfficialLink(context, s.url!);
    }
  }

  /// The day as a timeline: one block per hour (a « Maintenant » marker on
  /// today), cards side by side on wide screens.
  Widget _timeline(BuildContext context, List<ScheduleSlot> slots,
      List<LibraryEntry> entries, DateTime dayStart) {
    final now = DateTime.now();
    final isToday = dayStart.year == now.year && dayStart.month == now.month &&
        dayStart.day == now.day;
    final groups = <String, List<ScheduleSlot>>{};
    for (final s in slots) {
      final key = s.timeKnown ? '${two(s.at.toLocal().hour)}:00' : 'Dans la journée';
      groups.putIfAbsent(key, () => []).add(s);
    }
    final keys = groups.keys.toList();
    final rows = <Widget>[
      _daySummary(context, slots, entries),
    ];
    var nowShown = !isToday;
    for (final k in keys) {
      final list = groups[k]!;
      final hour = int.tryParse(k.split(':').first);
      if (!nowShown && hour != null && hour > now.hour) {
        rows.add(_nowMarker(context, now));
        nowShown = true;
      }
      rows.add(_hourBlock(context, k, list, entries,
          past: isToday && hour != null && hour < now.hour));
      if (!nowShown && hour != null && hour == now.hour) {
        rows.add(_nowMarker(context, now));
        nowShown = true;
      }
    }
    return SliverList.list(children: rows);
  }

  Widget _daySummary(BuildContext context, List<ScheduleSlot> slots, List<LibraryEntry> entries) {
    final p = context.pal;
    final anime = slots.where((s) => s.kind == SlotKind.anime).length;
    final comics = slots.length - anime;
    final mine = slots.where((s) => WeeklyScheduleBuilder.followed(s, entries)).length;
    final out = slots.where((s) => s.state == SlotState.released).length;
    Widget chip(IconData icon, String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PazuluRadius.card),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(Icons.event_available_rounded, '${slots.length} sorties', p.bright),
        if (anime > 0) chip(Icons.live_tv_rounded, '$anime animés', p.accent),
        if (comics > 0) chip(Icons.menu_book_rounded, '$comics chapitres', p.primary),
        chip(Icons.check_circle_rounded, '$out déjà sorties', p.success),
        if (mine > 0 && !_mine) chip(Icons.bookmark_rounded, '$mine de ma liste', p.warning),
      ]),
    );
  }

  Widget _nowMarker(BuildContext context, DateTime now) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: p.accent, border: Border.all(color: p.ink, width: 2)),
          child: Text('MAINTENANT · ${clockTime(now)}', style: TextStyle(
              color: p.onAccent, fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        Expanded(child: Container(height: 2.5, color: p.ink)),
      ]),
    );
  }

  Widget _hourBlock(BuildContext context, String label, List<ScheduleSlot> list,
      List<LibraryEntry> entries, {bool past = false}) {
    final p = context.pal;
    // Followed series first in each hour, then released before upcoming.
    final ordered = [...list]..sort((a, b) {
        final fa = WeeklyScheduleBuilder.followed(a, entries) ? 0 : 1;
        final fb = WeeklyScheduleBuilder.followed(b, entries) ? 0 : 1;
        if (fa != fb) return fa - fb;
        return a.at.compareTo(b.at);
      });
    final expanded = _expandedHours.contains(label);
    final shown = expanded ? ordered : ordered.take(8).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Hour header: big, high contrast, like a TV guide.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: past ? p.surface : p.selected,
            borderRadius: BorderRadius.circular(PazuluRadius.card),
          ),
          child: Row(children: [
            Text(label, style: TextStyle(
              fontSize: label.length > 5 ? 15 : 24,
              fontWeight: FontWeight.w900,
              color: past ? p.muted : p.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
            const SizedBox(width: 12),
            Text('${list.length} sortie${list.length > 1 ? 's' : ''}',
                style: TextStyle(color: past ? p.muted : p.bright, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (past) Text('passé', style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 6),
        for (final s in shown)
          _slotRow(context, s, followed: WeeklyScheduleBuilder.followed(s, entries), past: past),
        if (ordered.length > 8)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() =>
                  expanded ? _expandedHours.remove(label) : _expandedHours.add(label)),
              icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(expanded ? 'Réduire' : 'Voir ${ordered.length - 8} de plus'),
            ),
          ),
      ]),
    );
  }

  /// One release on one readable line: cover · title · chapter · when ·
  /// language · state. Large text, nothing overlapping.
  Widget _slotRow(BuildContext context, ScheduleSlot s, {bool followed = false, bool past = false}) {
    final p = context.pal;
    final color = switch (s.state) {
      SlotState.released => p.success,
      SlotState.scheduled => p.bright,
      SlotState.estimated => p.warning,
    };
    final released = s.state == SlotState.released || s.at.isBefore(DateTime.now());
    final when = released
        ? (s.timeKnown ? 'sorti ${releaseAge(s.at)}' : 'sorti aujourd\'hui')
        : (s.timeKnown ? '${s.state == SlotState.estimated ? 'vers ' : ''}${clockTime(s.at)} · ${countdown(s.at)}'
            : 'heure inconnue');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: followed ? p.warning.withValues(alpha: 0.08) : p.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openSlot(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(children: [
              SizedBox(
                width: 40,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: s.coverUrl == null
                      ? ColoredBox(color: p.surfaceHigh, child: Icon(
                          s.kind == SlotKind.anime ? Icons.live_tv_rounded : Icons.menu_book_rounded,
                          size: 18, color: p.muted))
                      : Image.network(s.coverUrl!, fit: BoxFit.cover, cacheWidth: 96,
                          errorBuilder: (_, __, ___) => ColoredBox(color: p.surfaceHigh)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (followed) Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.bookmark_rounded, size: 16, color: p.warning),
                    ),
                    Expanded(child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
                            color: past && !released ? p.muted : p.text))),
                  ]),
                  const SizedBox(height: 2),
                  Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.bright, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: TextStyle(color: p.text.withValues(alpha: 0.85), fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 34,
                child: s.kind == SlotKind.anime
                    ? Icon(Icons.live_tv_rounded, size: 18, color: p.accent)
                    : LangBadge(s.lang),
              ),
              const SizedBox(width: 6),
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(PazuluRadius.chip),
                ),
                child: Text(s.state.label, style: TextStyle(color: color, fontSize: 12,
                    fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Pauses, hiatus, comebacks and new seasons of the followed works.
  List<Widget> _statusSection(BuildContext context) {
    final app = AppScope.of(context);
    final statuses = [
      ...app.releaseForecast(langs: const ['en', 'fr']),
      ...app.animeReleases(),
    ].where(_isStatus).toList()
      ..sort((a, b) => a.state.index.compareTo(b.state.index));
    if (statuses.isEmpty) return const [];
    return [
      const SectionHeader('Reprises et nouvelles saisons',
          padding: EdgeInsets.fromLTRB(0, 8, 0, 8)),
      for (final r in statuses) _releaseTile(context, r, status: true),
      const SizedBox(height: 12),
    ];
  }

  /// Only real news (a comeback, a new season). Paused, cancelled and
  /// finished series are not in the planning: Découvrir › Statut des séries.
  static bool _isStatus(PlannedRelease r) => r.state == ReleaseState.newSeason ||
      r.state == ReleaseState.resumed;

  Color _stateColor(BuildContext context, ReleaseState s) {
    final p = context.pal;
    return switch (s) {
      ReleaseState.confirmed => p.success,
      ReleaseState.announced => p.bright,
      ReleaseState.expected => p.muted,
      ReleaseState.late => p.warning,
      ReleaseState.pauseLikely => p.warning,
      ReleaseState.hiatus => p.danger,
      ReleaseState.resumed => p.success,
      ReleaseState.newSeason => p.accent,
    };
  }

  Widget _releaseTile(BuildContext context, PlannedRelease r, {bool status = false}) {
    final p = context.pal;
    final work = r.entry.work;
    final state = r.confirmed ? ReleaseState.confirmed : (r.isLate ? ReleaseState.late : r.state);
    final color = _stateColor(context, state);
    final String time;
    if (r.confirmed) {
      time = relativeTime(r.date);
    } else if (!r.dateKnown) {
      time = '—';
    } else if (status) {
      time = shortDate(r.date);
    } else if (r.timeKnown) {
      time = r.isAnime ? clockTime(r.date) : 'vers ${clockTime(r.date)}';
    } else {
      time = 'Journée';
    }
    final details = <String>[
      r.chapterLabel ?? (r.isAnime ? 'Prochain épisode' : 'Prochain chapitre'),
      if (!status && r.dateKnown && r.date.isAfter(DateTime.now()) &&
          (r.isAnime ? r.timeKnown : r.date.difference(DateTime.now()) < const Duration(days: 8)))
        r.timeKnown || r.isAnime ? countdown(r.date) : 'dans ~${countdown(r.date).replaceFirst('dans ', '')}',
      if (!r.isAnime && r.interval != null)
        'tous les ${r.interval!.inDays < 1 ? 1 : r.interval!.inDays} j',
      if (r.note != null) r.note!,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(PazuluRadius.card),
          onTap: () => pushPage(context, WorkPage(work: work,
              heroTag: 'plan-${work.id}-${r.lang}-${r.date.millisecondsSinceEpoch}-${r.state.index}')),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(PazuluRadius.card),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(time, maxLines: 2, style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: r.timeKnown && !status && !r.confirmed ? 16 : 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: r.timeKnown ? p.text : p.muted,
                  )),
                ),
                SizedBox(
                  width: 36,
                  height: 52,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: work.coverUrl == null
                        ? ColoredBox(color: p.surfaceHigh)
                        : Image.network(work.coverUrl!, fit: BoxFit.cover, cacheWidth: 80,
                            errorBuilder: (_, __, ___) => ColoredBox(color: p.surfaceHigh)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(details.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (r.isAnime)
                  Icon(Icons.live_tv_rounded, size: 16, color: p.muted)
                else
                  LangBadge(r.lang),
                const SizedBox(width: 8),
                Tag(state.label, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------- Mes lectures

  List<Widget> _reading(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final weekday = DateTime.now().weekday;
    final entries = app.entries.toList();
    final todayList = ReleasePlanner.plannedOn(entries, weekday);
    final unplanned = entries.where((e) => e.readingDays.isEmpty &&
        (e.status == TrackStatus.reading || e.status == TrackStatus.planned)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final langs = app.settings.comicLangs;

    return [
      SizedBox(
        height: 86,
        child: Row(
          children: [
            for (var d = 1; d <= 7; d++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Glass(
                    highlight: d == weekday,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_days[d - 1], style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: d == weekday ? p.bright : p.text)),
                        const SizedBox(height: 4),
                        Text('${ReleasePlanner.plannedOn(entries, d).length}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('œuvre(s)', style: TextStyle(color: p.muted, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SectionHeader('Aujourd\'hui · ${_longDays[weekday - 1]}',
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8)),
      if (todayList.isEmpty)
        Glass(child: Text('Rien de prévu aujourd\'hui. Planifiez une œuvre ci-dessous.',
            style: TextStyle(color: p.muted)))
      else
        for (final e in todayList) _readingTile(context, e, langs, today: true),
      const SectionHeader('Toutes mes lectures planifiées', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
      for (final e in entries.where((e) => e.readingDays.isNotEmpty))
        _readingTile(context, e, langs),
      if (unplanned.isNotEmpty) ...[
        const SectionHeader('En cours / à lire, sans planning', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
        for (final e in unplanned.take(40)) _readingTile(context, e, langs),
      ],
    ];
  }

  Widget _readingTile(BuildContext context, LibraryEntry e, List<String> langs,
      {bool today = false}) {
    final p = context.pal;
    final unread = ReleasePlanner.unreadEstimate(e, langs);
    final days = e.readingDays.isEmpty
        ? 'Non planifiée'
        : e.readingDays.map((d) => _days[d - 1]).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Glass(
        highlight: today,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.work.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('$days · objectif ${e.readingGoal} chapitre(s)'
                      '${unread > 0 ? ' · $unread non lu(s)' : ''}'
                      '${e.progress.lastKey == null ? '' : ' · dernier lu : ${e.progress.lastKey}'}',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _editPlan(context, e),
              icon: const Icon(Icons.edit_calendar_rounded, size: 18),
              label: const Text('Planifier'),
            ),
            FilledButton.icon(
              onPressed: () => pushPage(context, WorkPage(work: e.work,
                  heroTag: 'plan-read-${e.work.id}', autoResume: true)),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Lire'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPlan(BuildContext context, LibraryEntry e) async {
    final days = Set<int>.of(e.readingDays);
    var goal = e.readingGoal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Planifier « ${e.work.title} »'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Jours de lecture'),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_days[d - 1]),
                      selected: days.contains(d),
                      onSelected: (v) => setLocal(() => v ? days.add(d) : days.remove(d)),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Chapitres par séance : $goal'),
                Slider(
                  value: goal.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: '$goal',
                  onChanged: (v) => setLocal(() => goal = v.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      AppScope.read(context).setReadingPlan(e.work, days: days.toList(), goal: goal);
    }
  }
}
