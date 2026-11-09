import 'package:flutter/material.dart';

import '../core/suggested_sources.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'widgets/common.dart';

/// Searchable suggestions from a snapshot supplied by the user.
/// Not advertised as working native source plugins: those need individual tests.
class SuggestedSourcesPage extends StatefulWidget {
  const SuggestedSourcesPage({super.key});

  @override
  State<SuggestedSourcesPage> createState() => _SuggestedSourcesPageState();
}

class _SuggestedSourcesPageState extends State<SuggestedSourcesPage> {
  late final Future<List<SuggestedSource>> _catalog = SuggestedSourceCatalog.load();
  final _search = TextEditingController();
  String _language = 'all';
  String _status = 'all';
  bool _adding = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add(SuggestedSource site) async {
    if (_adding) return;
    final app = AppScope.read(context);
    setState(() => _adding = true);
    try {
      await app.addPersonalSource(
        url: site.url,
        name: site.displayName,
        languages: [site.language],
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${site.displayName} ajoute a tes sources. La lecture devra etre verifiee.'),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ajout impossible : $error'),
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = AppScope.of(context);
    final hosts = {
      for (final site in app.activeSources)
        Uri.parse(site.home).host.replaceFirst(RegExp(r'^www\.'), ''),
    };
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Catalogue de 200 sites')),
      body: FutureBuilder<List<SuggestedSource>>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Catalogue indisponible : ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final query = _search.text.trim().toLowerCase();
          final filtered = snapshot.data!.where((s) =>
            (_language == 'all' || s.language == _language) &&
            (_status == 'all' ||
              (_status == 'reported' && s.isReportedAccessible) ||
              (_status == 'uncertain' && !s.isReportedAccessible)) &&
            (query.isEmpty || s.host.contains(query) || s.category.toLowerCase().contains(query))
          ).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Suggestions de sources FR / EN',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Liste fournie le 5 novembre 2026. Un accueil accessible '
                  'ne garantit ni les chapitres ni leur lecture dans Pazulu. '
                  'Ces sites ne sont pas 200 connecteurs installes. '
                  'Tu les ajoutes au cas par cas.',
                  style: TextStyle(color: p.muted)),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Rechercher un domaine ou un type de contenu',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final f in const [('all','FR + EN'),('fr','FR'),('en','EN')])
                    ChoiceChip(label: Text(f.$2), selected: _language == f.$1,
                      onSelected: (_) => setState(() => _language = f.$1)),
                  const SizedBox(width: 6),
                  ChoiceChip(label: const Text('Tous les statuts'), selected: _status == 'all',
                    onSelected: (_) => setState(() => _status = 'all')),
                  ChoiceChip(label: const Text('Catalogue signale accessible'),
                    selected: _status == 'reported',
                    onSelected: (_) => setState(() => _status = 'reported')),
                  ChoiceChip(label: const Text('A verifier'), selected: _status == 'uncertain',
                    onSelected: (_) => setState(() => _status = 'uncertain')),
                ]),
                const SizedBox(height: 8),
                Text('${filtered.length} sites dans ce filtre',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final site = filtered[index];
                final present = hosts.contains(site.displayName);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: ListTile(
                      title: Text(site.displayName),
                      subtitle: Text('${site.language.toUpperCase()} · ${site.category}\n'
                        '${site.reportedStatus} (statut de la liste, non recontrole)',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                      leading: Icon(Icons.language_rounded, color: p.bright),
                      trailing: present
                        ? const Icon(Icons.check_circle_outline_rounded)
                        : FilledButton.tonal(
                            onPressed: _adding ? null : () => _add(site),
                            child: const Text('Ajouter'),
                          ),
                      isThreeLine: true,
                    ),
                  ),
                );
              },
            )),
          ]);
        },
      ),
    );
  }
}
