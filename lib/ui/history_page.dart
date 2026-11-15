import 'package:flutter/material.dart';

import '../core/library_insights.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'read_actions.dart';

/// Historique de lecture, façon navigateur : quels chapitres, quand.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _query = '';

  static const _months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  static const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    final base = '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final q = _query.trim().toLowerCase();
    final items = <HistoryItem>[
      for (final h in app.history)
        if (q.isEmpty || h.title.toLowerCase().contains(q)) h,
    ].take(1500).toList();
    final rows = <Widget>[];
    String? lastDay;
    for (final h in items) {
      final day = _dayLabel(h.at);
      if (day != lastDay) {
        lastDay = day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
          child: Text(day.toUpperCase(),
              style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ));
      }
      final time = '${h.at.hour.toString().padLeft(2, '0')}:${h.at.minute.toString().padLeft(2, '0')}';
      final entry = app.entry(h.workId);
      rows.add(ListTile(
        dense: true,
        leading: Text(time, style: TextStyle(color: p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        title: Text(h.title.isEmpty ? (entry?.work.title ?? h.workId) : h.title),
        subtitle: Text('${h.chapterLabel}${h.finished ? ' · terminé' : ''}'),
        trailing: Icon(h.finished ? Icons.check_circle_rounded : Icons.play_circle_outline_rounded,
            size: 18, color: h.finished ? p.success : p.muted),
        onTap: entry == null
            ? null
            : () => resumeInPazulu(context, entry.work, chapterHint: h.chapterId, exactPage: 0),
      ));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique de lecture'),
        actions: [
          if (app.history.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Effacer l\'historique ?'),
                    content: const Text('Les chapitres lus et ta progression ne changent pas.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) AppScope.read(context).clearHistory();
              },
              child: const Text('Effacer'),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.sm, PazuluSpace.lg, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Filtrer par titre…'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('Rien pour l\'instant : chaque chapitre ouvert apparaîtra ici.',
                  style: TextStyle(color: p.muted)))
              : ListView(padding: const EdgeInsets.symmetric(horizontal: PazuluSpace.lg, vertical: 8), children: rows),
        ),
      ]),
    );
  }
}
