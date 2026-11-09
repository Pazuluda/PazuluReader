import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/source_catalog.dart';
import '../core/source_health.dart';
import '../core/user_sources.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'native_engine_page.dart';
import 'source_browser_page.dart';
import 'widgets/common.dart';

/// One source manager, without changing the existing Pazulu navigation/DA.
class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  String _lang = 'all';
  String _group = 'all';
  final _query = TextEditingController();
  bool _showDisabled = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _importRecipes() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], withData: true,
    );
    if (file == null || !mounted) return;
    final bytes = file.files.single.bytes;
    if (bytes == null || bytes.length > 250000) {
      _notice('Pack absent ou trop volumineux.');
      return;
    }
    try {
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['recipes'] is List) {
        final changes = (decoded['recipes'] as List).where((r) =>
          r is Map && ((r['hostAliases'] is List &&
              (r['hostAliases'] as List).isNotEmpty) ||
              (r['homeOverride'] is String &&
              (r['homeOverride'] as String).isNotEmpty))).length;
        if (changes > 0) {
          final approved = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Changement de domaine'),
              content: Text('$changes profil(s) changent de domaine. '
                  'N’importe que des mises a jour fiables : un faux site '
                  'peut tenter de voler un compte.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuler')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Je confirme')),
              ],
            ),
          );
          if (approved != true || !mounted) return;
        }
      }
      final count = await AppScope.read(context).importSourceRecipes(text);
      if (mounted) _notice('$count profil(s) mis a jour.');
    } catch (e) {
      if (mounted) _notice('Pack refuse : $e');
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addSite() async {
    final url = TextEditingController();
    final name = TextEditingController();
    var fr = true;
    var en = true;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, change) => AlertDialog(
            title: const Text('Ajouter une source'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Colle simplement l’adresse du site. '
                      'Pazulu utilisera son moteur commun de lecture quand '
                      'la source le permet.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: url,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Adresse HTTPS du site *',
                      hintText: 'https://exemple.com/',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nom (facultatif)', hintText: 'Detecte depuis le domaine',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, children: [
                    FilterChip(label: const Text('FR'), selected: fr,
                        onSelected: (v) => change(() => fr = v)),
                    FilterChip(label: const Text('EN'), selected: en,
                        onSelected: (v) => change(() => en = v)),
                  ]),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error)),
                  ],
                  const SizedBox(height: 6),
                  const Text('Ajouter un site ne garantit pas que ses chapitres '
                      'soient lisibles ou telechargeables. Le site sera teste '
                      'sans contourner ses restrictions.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter'),
                onPressed: () async {
                  if (!fr && !en) {
                    change(() => error = 'Choisis au moins une langue.');
                    return;
                  }
                  try {
                    final app = AppScope.read(context);
                    final added = await app.addPersonalSource(
                      url: url.text, name: name.text,
                      languages: [if (fr) 'fr', if (en) 'en'],
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) {
                      _notice('${added.title} ajoute. Verification disponible.');
                    }
                  } catch (e) {
                    change(() => error = e.toString().replaceFirst('FormatException: ', ''));
                  }
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      // Dispose after the dialog route has finished rather than while it animates.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        url.dispose();
        name.dispose();
      });
    }
  }

  Future<void> _open(CatalogSite site) async {
    final app = AppScope.read(context);
    await pushPage(context, SourceBrowserPage(
      siteId: site.id, title: site.title,
      url: app.extensionRecipes.forSite(site.id).homeOverride ?? site.home,
    ));
  }

  String _statusLabel(SourceHealth? health) {
    if (health == null) return 'Non verifie';
    return switch (health.status) {
      SourceHealthStatus.unknown => 'Non verifie',
      SourceHealthStatus.reachable => 'Site accessible',
      SourceHealthStatus.blocked => 'Acces limite / redirection',
      SourceHealthStatus.unstable => 'Incident temporaire possible',
      SourceHealthStatus.suspectedOffline => 'Indisponibilite persistante',
    };
  }

  IconData _statusIcon(SourceHealth? health) => switch (health?.status) {
    SourceHealthStatus.reachable => Icons.check_circle_outline_rounded,
    SourceHealthStatus.blocked => Icons.shield_outlined,
    SourceHealthStatus.unstable => Icons.warning_amber_rounded,
    SourceHealthStatus.suspectedOffline => Icons.cloud_off_outlined,
    _ => Icons.help_outline_rounded,
  };

  Future<void> _editSite(CatalogSite site) async {
    final app = AppScope.read(context);
    final matching = app.personalSources.where((s) => s.id == site.id).toList();
    if (matching.isEmpty) return;
    final current = matching.single;
    final url = TextEditingController(text: current.url);
    final name = TextEditingController(text: current.name);
    var fr = current.languages.contains('fr');
    var en = current.languages.contains('en');
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, change) => AlertDialog(
            title: const Text('Modifier ma source'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Adresse HTTPS'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: name,
                      decoration: const InputDecoration(labelText: 'Nom')),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, children: [
                    FilterChip(label: const Text('FR'), selected: fr,
                        onSelected: (v) => change(() => fr = v)),
                    FilterChip(label: const Text('EN'), selected: en,
                        onSelected: (v) => change(() => en = v)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Les chapitres et liens deja sauvegardes ne sont '
                      'jamais remplaces automatiquement.',
                      style: TextStyle(fontSize: 12)),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              FilledButton(
                onPressed: () async {
                  if (!fr && !en) {
                    change(() => error = 'Choisis au moins une langue.');
                    return;
                  }
                  try {
                    final next = normalizedSourceUri(url.text);
                    final previous = Uri.parse(current.url);
                    if (next.host != previous.host) {
                      final accepted = await showDialog<bool>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          title: const Text('Nouveau domaine'),
                          content: Text('Ancien : ${previous.host}\n'
                              'Nouveau : ${next.host}\n\n'
                              'Verifie que ce site est fiable avant de '
                              'te connecter. Les anciens liens de lecture '
                              'ne seront pas remplaces automatiquement.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx, false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(confirmCtx, true),
                              child: const Text('Confirmer'),
                            ),
                          ],
                        ),
                      );
                      if (accepted != true || !ctx.mounted) return;
                    }
                    final saved = await app.updatePersonalSource(
                      id: current.id, url: next.toString(),
                      name: name.text.trim(),
                      languages: [if (fr) 'fr', if (en) 'en'],
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _notice('${saved.title} modifiee.');
                  } catch (e) {
                    if (ctx.mounted) change(() => error =
                      e.toString().replaceFirst('FormatException: ', ''));
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        url.dispose();
        name.dispose();
      });
    }
  }

  Future<void> _details(CatalogSite site, SourceHealth? health) async {
    final app = AppScope.read(context);
    final own = app.personalSources.where((s) => s.id == site.id).toList();
    final enabled = own.isEmpty || own.single.enabled;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(site.title),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(site.home),
              const SizedBox(height: 12),
              Text('Etat : ${_statusLabel(health)}'),
              if (health?.checkedAt != null)
                Text('Dernier controle : ${health!.checkedAt.toLocal()}'),
              if (health?.httpStatus != null)
                Text('Code HTTP : ${health!.httpStatus}'),
              if (health?.note != null) Text(health!.note!),
              if (health?.failures != null && health!.failures > 0)
                Text('Echecs consecutifs observes : ${health.failures}'),
              const SizedBox(height: 8),
              const Text('Une erreur reseau, une page blanche ou un code '
                  '403/525 ne prouvent pas une fermeture definitive.'),
            ],
          ),
        ),
        actions: [
          if (own.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'edit'),
              child: const Text('Modifier'),
            ),
          if (own.isNotEmpty)
            TextButton(
              onPressed: () async {
                await app.setPersonalSourceEnabled(site.id, !enabled);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(enabled ? 'Desactiver' : 'Reactiver'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
          FilledButton(
            onPressed: app.checkingSources || !enabled ? null : () async {
              Navigator.pop(ctx);
              await app.checkSourceHealth(siteId: site.id, force: true);
              if (mounted) _notice('Verification de ${site.title} terminee.');
            },
            child: const Text('Verifier maintenant'),
          ),
        ],
      ),
    );
    if (action == 'edit' && mounted) await _editSite(site);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = AppScope.of(context);
    final recipes = app.extensionRecipes;
    final all = [
      ...app.activeSources,
      if (_showDisabled)
        ...app.personalSources.where((site) => !site.enabled)
            .map((site) => site.toCatalogSite()),
    ];
    final query = _query.text.toLowerCase().trim();
    final visible = all.where((site) {
      if (_lang != 'all' && !site.languages.contains(_lang)) return false;
      if (_group == 'curated' && !catalogSites.any((s) => s.id == site.id)) {
        return false;
      }
      if (_group == 'directory' && !site.id.startsWith('directory_')) {
        return false;
      }
      if (_group == 'personal' && !site.id.startsWith('user_')) {
        return false;
      }
      if (query.isNotEmpty &&
          !site.title.toLowerCase().contains(query) &&
          !site.home.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Sources de lecture')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  PazuluSpace.lg, PazuluSpace.lg, PazuluSpace.lg, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mes sources', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Les 200 adresses de ta liste sont maintenant accessibles directement '
                    'ici : 196 nouvelles et 4 deja repertoriees. '
                    'Les sites sont des adresses de lecture, pas 200 connecteurs '
                    'valides. Aucun chapitre n’est telecharge pendant la recherche.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: PazuluSpace.md),
                  TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Rechercher un site parmi les 200...',
                    ),
                  ),
                  const SizedBox(height: PazuluSpace.sm),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () => pushPage(context, const NativeEnginePage()),
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: const Text('Moteur Pazulu · intégré'),
                    ),
                    FilledButton.icon(
                      onPressed: _addSite,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ajouter un autre site'),
                    ),
                    OutlinedButton.icon(
                      onPressed: app.checkingSources ? null : () =>
                          app.checkSourceHealth(force: true),
                      icon: app.checkingSources
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                      label: Text(app.checkingSources
                          ? 'Verification en cours' : 'Verifier mes sources suivies'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importRecipes,
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Mettre a jour les profils (.json)'),
                    ),
                  ]),
                  const SizedBox(height: PazuluSpace.sm),
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final filter in const [
                      ('all', 'Toutes'), ('curated', 'Les 13 initiales'),
                      ('directory', 'Annuaire ajoute'),
                      ('personal', 'Mes ajouts'),
                    ])
                      ChoiceChip(
                        label: Text(filter.$2),
                        selected: _group == filter.$1,
                        onSelected: (_) => setState(() => _group = filter.$1),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final filter in const [
                      ('all', 'FR + EN'), ('fr', 'FR'), ('en', 'EN'),
                    ])
                      ChoiceChip(
                        label: Text(filter.$2),
                        selected: _lang == filter.$1,
                        onSelected: (_) => setState(() => _lang = filter.$1),
                      ),
                    FilterChip(
                      label: const Text('Mes sources desactivees'),
                      selected: _showDisabled,
                      onSelected: (v) => setState(() => _showDisabled = v),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text('${visible.length} sources affichees · '
                      'Recherche automatique des œuvres : MangaDex et Pepper&Carrot. '
                      'Les autres sites se consultent dans la fenetre Pazulu.',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(PazuluSpace.lg),
              child: Text('Aucune source pour cette recherche.',
                  style: TextStyle(color: p.muted)),
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  PazuluSpace.lg, 0, PazuluSpace.lg, PazuluSpace.lg),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final site = visible[i];
                  final directory = site.id.startsWith('directory_');
                  final recipe = recipes.forSite(site.id);
                  final capability = site.hasReaderConnector
                      ? 'Connecteur natif'
                      : directory
                          ? 'Adresse repertoriee · lecture a verifier'
                          : recipe.mode == 'official'
                              ? 'Acces officiel'
                              : 'Exploration du site (experimental)';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: PazuluSpace.sm),
                    child: Glass(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(site.hasReaderConnector
                            ? Icons.auto_stories_rounded
                            : Icons.language_rounded, color: p.bright),
                        title: Text(site.title, maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${site.languages.map((s) => s.toUpperCase()).join(' / ')}'
                                ' · $capability',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 12)),
                            Row(children: [
                              Icon(_statusIcon(app.healthFor(site.id)),
                                  size: 14, color: p.muted),
                              const SizedBox(width: 5),
                              Flexible(child: Text(_statusLabel(app.healthFor(site.id)),
                                  style: TextStyle(color: p.muted, fontSize: 12))),
                            ]),
                          ],
                        ),
                        trailing: IconButton(
                          tooltip: 'Etat, verification et gestion',
                          icon: Icon(Icons.more_vert_rounded, color: p.muted),
                          onPressed: () => _details(site, app.healthFor(site.id)),
                        ),
                        onTap: () => _open(site),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
