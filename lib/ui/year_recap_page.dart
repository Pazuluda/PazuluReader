import 'package:flutter/material.dart';

import '../core/recap.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'widgets/common.dart';

/// « Mon année » : le récap façon Wrapped (chapitres, temps, jours,
/// séries, œuvres préférées, genre favori, meilleur mois).
class YearRecapPage extends StatefulWidget {
  const YearRecapPage({super.key});

  @override
  State<YearRecapPage> createState() => _YearRecapPageState();
}

class _YearRecapPageState extends State<YearRecapPage> {
  int _year = DateTime.now().year;

  static const _months = ['', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final YearRecap r = app.yearRecap(_year);
    Widget big(String value, String label, IconData icon) => Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: p.bright),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: p.muted)),
          ]),
        );
    final hours = (r.minutes / 60).round();
    return Scaffold(
      appBar: AppBar(
        title: Text('Mon année $_year'),
        actions: [
          IconButton(tooltip: 'Année précédente', icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() => _year--)),
          IconButton(tooltip: 'Année suivante', icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _year >= DateTime.now().year ? null : () => setState(() => _year++)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(PazuluSpace.lg), children: [
            Text(r.chapters == 0 ? 'Pas encore de lecture enregistrée en $_year.' : 'Ton année en lecture',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: PazuluSpace.md),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                big('${r.chapters}', 'chapitres lus', Icons.auto_stories_rounded),
                big('≈ $hours h', 'de lecture', Icons.schedule_rounded),
                big('${r.activeDays}', 'jours de lecture', Icons.calendar_month_rounded),
                big('${r.bestStreak} j', 'plus longue série', Icons.local_fire_department_rounded),
                big('${r.newWorks}', 'nouvelles œuvres', Icons.fiber_new_rounded),
                big('${r.finishedSeries}', 'séries terminées', Icons.flag_rounded),
              ],
            ),
            if (r.bestMonth > 0) ...[
              const SizedBox(height: PazuluSpace.lg),
              Text('Meilleur mois : ${_months[r.bestMonth]} (${r.bestMonthCount} chapitres)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
            if (r.topGenre != null) ...[
              const SizedBox(height: 8),
              Text('Genre préféré : ${r.topGenre}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
            if (r.topWorks.isNotEmpty) ...[
              const SizedBox(height: PazuluSpace.lg),
              const SectionHeader('Tes œuvres les plus lues', padding: EdgeInsets.only(bottom: 8)),
              for (var i = 0; i < r.topWorks.length; i++)
                ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(r.topWorks[i].$1),
                  trailing: Text('${r.topWorks[i].$2} ch.', style: TextStyle(color: p.muted)),
                ),
            ] else if (r.chapters > 0)
              Padding(
                padding: const EdgeInsets.only(top: PazuluSpace.lg),
                child: Text('Le classement des œuvres se remplit avec l\'historique de lecture (depuis la 1.7.0).',
                    style: TextStyle(color: p.muted)),
              ),
          ]),
        ),
      ),
    );
  }
}
