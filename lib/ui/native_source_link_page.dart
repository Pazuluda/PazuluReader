import 'package:flutter/material.dart';

import '../core/discovery.dart';
import '../core/models.dart';
import '../core/source.dart';
import '../design/theme.dart';
import 'app_scope.dart';

class NativeSourceLinkPage extends StatefulWidget {
  const NativeSourceLinkPage({super.key, required this.work});
  final WorkInfo work;

  @override
  State<NativeSourceLinkPage> createState() => _NativeSourceLinkPageState();
}

class _Match {
  const _Match(this.source, this.work, this.chapterCount, this.error);
  final ContentSource source;
  final WorkInfo work;
  final int chapterCount;
  final String? error;
}

class _NativeSourceLinkPageState extends State<NativeSourceLinkPage> {
  late final TextEditingController _query;
  final _directUrl = TextEditingController();
  final List<_Match> _matches = [];
  bool _searching = false;
  bool _linking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.work.title);
  }

  @override
  void dispose() {
    _query.dispose();
    _directUrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching || _query.text.trim().length < 2) return;
    setState(() { _searching = true; _matches.clear(); _error = null; });
    final app = AppScope.read(context);
    try {
      for (final source in app.nativeSources) {
        try {
          final results = await source.search(_query.text.trim(), limit: 25)
              .timeout(const Duration(seconds: 15));
          for (final work in results) {
            if (!sameWorkAcrossSources(widget.work, work) || work.links.isEmpty) continue;
            var count = 0;
            String? error;
            try {
              count = (await source.listChapters(work.links.first.workId,
                  langs: app.settings.comicLangs)
                  .timeout(const Duration(seconds: 20))).length;
            } catch (e) { error = '$e'; }
            _matches.add(_Match(source, work, count, error));
            break;
          }
        } catch (e) { _error = '${source.name} : $e'; }
      }
      _matches.sort((a, b) => b.chapterCount.compareTo(a.chapterCount));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _link(_Match match) async {
    if (_linking || match.work.links.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Associer cette édition ?'),
          content: Text('${match.work.title} · ${match.source.name}\n'
              '${match.chapterCount} volumes/chapitres détectés.\n\n'
              'La progression existante sera conservée.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Associer')),
          ],
        ));
    if (confirmed != true || !mounted) return;
    setState(() => _linking = true);
    try {
      await AppScope.read(context).linkNativeEdition(widget.work, match.work.links.first);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Association impossible : $e')));
    } finally { if (mounted) setState(() => _linking = false); }
  }

  /// Any site: the address of the series page (mgeko, asura, a French
  /// scan…). SushiScan.net keeps its own connector.
  Future<void> _linkExactUrl() async {
    if (_linking) return;
    final url = _directUrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _linking = true);
    try {
      final result = await AppScope.read(context).linkSiteUrl(widget.work, url)
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Site ajouté — $result')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Site non ajouté : $error')));
    } finally { if (mounted) setState(() => _linking = false); }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.pal;
    return Scaffold(backgroundColor: palette.background,
      appBar: AppBar(title: const Text('Ajouter un site')),
      body: Padding(padding: const EdgeInsets.all(PazuluSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rechercher une édition pour ${widget.work.title}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _query,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Titre ou titre alternatif',
              suffixIcon: IconButton(onPressed: _search,
                  icon: const Icon(Icons.arrow_forward_rounded)),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 16),
          Text('Ou coller l’adresse de la page de la série sur n’importe quel site '
              '(ex. https://www.mgeko.cc/manga/catastrophic-necromancer/) :',
              style: TextStyle(color: palette.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: _directUrl,
              decoration: const InputDecoration(
                hintText: 'https://site.com/manga/nom-de-la-serie/',
                prefixIcon: Icon(Icons.link_rounded)),
              onSubmitted: (_) => _linkExactUrl(),
            )),
            const SizedBox(width: 8),
            FilledButton(onPressed: _linking ? null : _linkExactUrl,
                child: Text(_linking ? 'LECTURE…' : 'AJOUTER CE SITE')),
          ]),
          const SizedBox(height: 12),
          if (_searching) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: palette.muted)),
          const SizedBox(height: 12),
          Expanded(child: ListView.builder(itemCount: _matches.length,
            itemBuilder: (context, index) {
              final match = _matches[index];
              return Card(child: ListTile(
                title: Text(match.work.title),
                subtitle: Text('${match.source.name} · '
                    '${match.chapterCount} volumes/chapitres'
                    '${match.error == null ? '' : ' · ${match.error}'}'),
                trailing: TextButton(onPressed: _linking ? null : () => _link(match),
                    child: const Text('Associer')),
              ));
            },
          )),
        ]),
      ),
    );
  }
}
