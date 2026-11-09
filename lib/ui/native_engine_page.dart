import 'package:flutter/material.dart';

import '../core/source.dart';
import '../design/theme.dart';
import 'app_scope.dart';

/// Source diagnostics run inside Pazulu Reader, without any external engine.
class NativeEnginePage extends StatefulWidget {
  const NativeEnginePage({super.key});

  @override
  State<NativeEnginePage> createState() => _NativeEnginePageState();
}

class _NativeEnginePageState extends State<NativeEnginePage> {
  final _query = TextEditingController(text: 'Solo Leveling');
  final Map<String, String> _reports = {};
  final Set<String> _checking = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _test(ContentSource source) async {
    final q = _query.text.trim();
    if (q.length < 2 || _checking.contains(source.id)) return;
    setState(() {
      _checking.add(source.id);
      _reports.remove(source.id);
    });
    try {
      final matches = await source.search(q, limit: 20)
          .timeout(const Duration(seconds: 20));
      if (matches.isEmpty) {
        if (mounted) setState(() => _reports[source.id] = 'Aucune fiche trouvée.');
        return;
      }
      final exact = matches.where((work) =>
          work.title.toLowerCase().trim() == q.toLowerCase()).toList();
      if (exact.length != 1 || exact.single.links.isEmpty) {
        if (mounted) setState(() => _reports[source.id] =
            '${matches.length} résultat(s). Recherche plus précise nécessaire.');
        return;
      }
      final link = exact.single.links.first;
      final chapters = await source.listChapters(link.workId,
          langs: const ['fr', 'en']).timeout(const Duration(seconds: 25));
      if (chapters.isEmpty) {
        if (mounted) setState(() => _reports[source.id] =
            'Fiche trouvée, aucun chapitre retourné.');
        return;
      }
      // Read a page list only for explicit diagnostics. No image download.
      var pages = 0;
      String? issue;
      try {
        final refs = await source.getPages(chapters.first)
            .timeout(const Duration(seconds: 20));
        pages = refs.length;
      } catch (error) {
        issue = '$error';
      }
      if (mounted) setState(() => _reports[source.id] =
          '${chapters.length} éléments trouvés · $pages URL(s) de pages '
          '${issue == null ? 'sur le premier' : '· Images non vérifiées : $issue'}. '
          'Le chargement binaire reste à valider en ouvrant le lecteur.');
    } catch (error) {
      if (mounted) setState(() => _reports[source.id] = 'Erreur : $error');
    } finally {
      if (mounted) setState(() => _checking.remove(source.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final palette = context.pal;
    final sources = app.nativeSources;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: const Text('Moteur Pazulu · intégré')),
      body: ListView(padding: const EdgeInsets.all(PazuluSpace.lg), children: [
        Text('Aucun serveur. Aucune extension APK.',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Ces connecteurs Dart font partie de Pazulu Reader. '
             'Un site du répertoire n’est pas un connecteur fonctionnel tant '
             'que son test de chapitres et de pages n’est pas validé.',
             style: TextStyle(color: palette.muted)),
        const SizedBox(height: 18),
        TextField(controller: _query,
          decoration: const InputDecoration(
            labelText: 'Tester un titre',
            prefixIcon: Icon(Icons.search_rounded)),
          onSubmitted: (_) { for (final source in sources) { _test(source); } },
        ),
        const SizedBox(height: 12),
        for (final source in sources) Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_stories_rounded),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(source.languages.map((e) => e.toUpperCase()).join(' · '),
                      style: TextStyle(color: palette.muted, fontSize: 12)),
                ])),
              OutlinedButton.icon(
                onPressed: _checking.contains(source.id) ? null : () => _test(source),
                icon: _checking.contains(source.id)
                  ? const SizedBox(height: 14, width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.fact_check_outlined, size: 17),
                label: const Text('Tester'),
              ),
            ]),
            if (_reports[source.id] != null) ...[
              const SizedBox(height: 8),
              Text(_reports[source.id]!, style: TextStyle(color: palette.muted)),
            ],
          ]),
        )),
        const SizedBox(height: 16),
        Text('Les adresses web du catalogue restent disponibles pour '
             'consultation, sans être présentées comme des lecteurs natifs.',
             style: TextStyle(color: palette.muted)),
      ]),
    );
  }
}
