import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/browser_navigation.dart';
import '../core/chapters.dart';
import '../core/chapter_key.dart';
import '../core/chapter_identity.dart';
import '../core/page_inspection.dart';
import '../core/source_catalog.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'reader_page.dart';
import 'widgets/official_web_view.dart';

/// Site opened in Pazulu's SINGLE application window. An optional common
/// extension inspects images already present in the DOM after a user action.
/// The actual reading UI, when supported/authorized, is ReaderPage.
class SourceBrowserPage extends StatefulWidget {
  const SourceBrowserPage({super.key, required this.title, required this.url, this.siteId, this.workId});

  final String title;
  final String url;
  final String? siteId;
  final String? workId;

  @override
  State<SourceBrowserPage> createState() => _SourceBrowserPageState();
}

class _SourceBrowserPageState extends State<SourceBrowserPage> {
  EmbeddedBrowserBridge? _bridge;
  bool _inspecting = false;

  CatalogSite? get _site {
    final app = AppScope.read(context);
    if (widget.siteId != null) {
      final selected = app.siteById(widget.siteId!);
      if (selected != null &&
          app.extensionRecipes.forSite(selected.id).accepts(selected, widget.url)) {
        return selected;
      }
      return null;
    }
    for (final site in app.activeSources) {
      if (app.extensionRecipes.forSite(site.id).accepts(site, widget.url)) {
        return site;
      }
    }
    return null;
  }

  Future<void> _inspect() async {
    if (_inspecting) return;
    final site = _site;
    final bridge = _bridge;
    if (site == null || bridge == null) return;
    final app = AppScope.read(context);
    final recipe = app.extensionRecipes.forSite(site.id);
    if (!recipe.canInspect) return;
    setState(() => _inspecting = true);
    try {
      final raw = await bridge.run(makeInspectionScript(recipe));
      final inspection = PageInspection.fromBrowser(raw, site, recipe: recipe);
      if (!mounted) return;
      // A native Windows HWND always draws above Flutter dialogs/routes.
      // Hide it BEFORE opening any dialog or our custom reader.
      await bridge.setVisible(false);
      if (!mounted) return;
      final decision = await _captureDialog(site, inspection);
      if (!mounted) return;
      if (decision != null) {
        final targetWork = decision.workId == null
            ? null : app.entry(decision.workId!)?.work;
        final (work, chapter) = app.registerBrowserCapture(
          site, inspection, decision.lang,
          existingWork: targetWork,
          chapterKey: ChapterKey.parse(decision.chapter),
        );
        if (decision.action == 'download') {
          try {
            await app.downloadChapter(work, chapter);
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('CBZ indisponible : $e. Lecture en ligne si les images sont accessibles.')),
            );
          }
        }
        if (mounted) {
          final all = await app.chaptersFor(work, refresh: true);
          if (!mounted) return;
          final target = all.indexWhere((g) => g.key.id == chapter.key.id);
          await pushPage(context, ReaderPage(
            work: work,
            groups: target >= 0 ? all : [ChapterGroup(chapter.key, [chapter])],
            initialIndex: target >= 0 ? target : 0,
            initialPage: app.entry(work.id)?.progress.lastKey == chapter.key.id
                ? app.entry(work.id)!.progress.lastPage : 0,
            initialVariant: chapter,
          ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analyse impossible : $e')),
      );
    } finally {
      try { await _bridge?.setVisible(true); } catch (_) {}
      if (mounted) setState(() => _inspecting = false);
    }
  }

  /// Link an inspected chapter to a canonical work AND chapter number. This
  /// keeps all variants on a single reading timeline, even after a CBZ import.
  Future<_CaptureChoice?> _captureDialog(CatalogSite site, PageInspection inspection) async {
    final app = AppScope.read(context);
    final entries = app.entries.toList()
      ..sort((a, b) => a.work.title.compareTo(b.work.title));
    final suggested = ChapterIdentity.detect(
      title: inspection.title, url: inspection.pageUrl,
    )?.id ?? '';
    final chapter = TextEditingController(text: suggested);
    final title = inspection.title.toLowerCase();
    final matched = entries.where((e) =>
        title.contains(e.work.title.toLowerCase()) ||
        e.work.altTitles.any((a) => a.length > 5 && title.contains(a.toLowerCase()))).toList();
    var workId = widget.workId != null && entries.any((e) => e.work.id == widget.workId)
        ? widget.workId! : (matched.length == 1 ? matched.first.work.id : '__new__');
    var lang = site.languages.length == 1 ? site.languages.first : 'en';
    String? error;
    try {
      return await showDialog<_CaptureChoice>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, change) => AlertDialog(
          title: const Text('Ouvrir dans le lecteur Pazulu'),
          content: SizedBox(width: 480, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${inspection.pages.length} images reconnues · ${site.title}',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: workId, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Associer à une œuvre'),
                items: [
                  const DropdownMenuItem(value: '__new__', child: Text('Nouvelle œuvre')),
                  for (final entry in entries)
                    DropdownMenuItem(value: entry.work.id,
                      child: Text(entry.work.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) { if (value != null) change(() => workId = value); },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: chapter,
                decoration: const InputDecoration(
                  labelText: 'Numéro du chapitre', hintText: 'Ex. 16 ou 115.5'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: lang,
                decoration: const InputDecoration(labelText: 'Langue'),
                items: [for (final value in site.languages)
                  DropdownMenuItem(value: value, child: Text(value.toUpperCase()))],
                onChanged: (value) { if (value != null) change(() => lang = value); },
              ),
              const SizedBox(height: 12),
              const Text('Le site doit autoriser l’utilisation des pages dans un autre lecteur. '
                'Aucune protection, connexion payante ou DRM ne sera contourne.'),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            TextButton(onPressed: () {
              if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(chapter.text.trim())) {
                change(() => error = 'Indique un numéro de chapitre valide.');
                return;
              }
              Navigator.pop(ctx, _CaptureChoice(
                'read', workId == '__new__' ? null : workId, lang, chapter.text));
            }, child: const Text('Lire maintenant')),
            FilledButton(onPressed: () {
              if (chapter.text.trim().isEmpty ||
                  !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(chapter.text.trim())) {
                change(() => error = 'Utilise un numero, par exemple 16 ou 16.5.');
                return;
              }
              Navigator.pop(ctx, _CaptureChoice(
                'download', workId == '__new__' ? null : workId, lang, chapter.text));
            }, child: const Text('CBZ et lire')),
          ],
        )),
      );
    } finally {
      chapter.dispose();
    }
  }

  /// Bind the *current* browser URL to a library item; no copying URLs or
  /// opening external browsers. The embedded native HWND must be hidden while
  /// the Flutter dialog is displayed (otherwise it obscures the dialog).
  Future<void> _linkCurrentPage() async {
    final bridge = _bridge;
    final site = _site;
    if (bridge == null || site == null) return;
    final app = AppScope.read(context);
    final works = app.entries.toList()..sort((a, b) =>
        a.work.title.toLowerCase().compareTo(b.work.title.toLowerCase()));
    if (works.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ajoutez d’abord une œuvre à votre bibliothèque.'),
      ));
      return;
    }
    try {
      final raw = await bridge.run('window.location.href');
      var actualUrl = raw.toString().trim();
      try {
        final decoded = jsonDecode(actualUrl);
        if (decoded is String) actualUrl = decoded;
      } catch (_) {
        // Mobile WebView sometimes returns an unquoted URL.
      }
      if (!site.accepts(actualUrl)) {
        throw const FormatException('La page actuelle ne fait pas partie du domaine sélectionné.');
      }
      if (!mounted) return;
      await bridge.setVisible(false);
      if (!mounted) return;
      var selectedWork = works.first.work.id;
      var selectedLang = site.languages.first;
      final linked = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, change) => AlertDialog(
            title: const Text('Associer cette fiche à une œuvre'),
            content: SizedBox(
              width: 430,
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(site.title),
                  const SizedBox(height: 8),
                  Text(actualUrl, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(dialogContext).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedWork,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Œuvre de ma bibliothèque'),
                    items: [for (final e in works)
                      DropdownMenuItem(value: e.work.id,
                        child: Text(e.work.title, overflow: TextOverflow.ellipsis))],
                    onChanged: (value) { if (value != null) change(() => selectedWork = value); },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedLang,
                    decoration: const InputDecoration(labelText: 'Langue des chapitres'),
                    items: [for (final lang in site.languages)
                      DropdownMenuItem(value: lang, child: Text(lang.toUpperCase()))],
                    onChanged: (value) { if (value != null) change(() => selectedLang = value); },
                  ),
                  const SizedBox(height: 12),
                  const Text('Choisissez la fiche d’une œuvre, pas la page d’accueil '
                    'ou un chapitre isolé. La lecture du site reste indépendante du suivi.'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler')),
              FilledButton(
                onPressed: () {
                  final entry = works.firstWhere((e) => e.work.id == selectedWork);
                  final ok = app.addSiteLink(entry.work, site.id, actualUrl, selectedLang);
                  Navigator.pop(dialogContext, ok);
                },
                child: const Text('Associer'),
              ),
            ],
          ),
        ),
      );
      if (mounted && linked == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fiche associée. Elle sera prise en compte au prochain contrôle.'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Association impossible : $e')));
    } finally {
      try { await bridge.setVisible(true); } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final valid = safeReadingUri(widget.url) != null;
    final site = _site;
    final inspectable = site != null &&
        AppScope.of(context).extensionRecipes.forSite(site.id).canInspect;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (site != null)
            IconButton(
              tooltip: 'Associer cette page à une œuvre de ma bibliothèque',
              onPressed: _linkCurrentPage,
              icon: const Icon(Icons.add_link_rounded),
            ),
          if (inspectable)
            TextButton.icon(
              onPressed: _inspecting ? null : _inspect,
              icon: _inspecting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_stories_rounded),
              label: const Text('Lire dans Pazulu'),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 16),
            child: Center(
              child: Text('LECTURE INTEGREE', style: TextStyle(color: p.muted,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ),
        ],
      ),
      body: valid
          ? OfficialWebView(
              url: widget.url,
              onScriptRunner: (runner) => _bridge = runner,
              fallback: const Center(child: Text('Affichage integre indisponible.')),
            )
          : const Center(child: Text('Cette adresse HTTPS n\'est pas valide.')),
    );
  }
}

class _CaptureChoice {
  const _CaptureChoice(this.action, this.workId, this.lang, this.chapter);
  final String action;
  final String? workId;
  final String lang;
  final String chapter;
}
