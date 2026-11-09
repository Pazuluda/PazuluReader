import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/log.dart';
import '../core/models.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'engine/diagnostics_page.dart';
import 'engine/extensions_page.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'widgets/update_dialog.dart';
import 'widgets/motion.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _knownLangs = ['en', 'fr'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final s = app.settings;
    final langs = s.comicLangs;
    var i = 0;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: PazuluSpace.lg),
          child: FadeSlideIn(
            index: i++,
            child: Glass(
              padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.md, PazuluSpace.lg, PazuluSpace.md),
              radius: PazuluRadius.big,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(), style: kiosqueDisplay(18, color: p.text)),
                  const SizedBox(height: PazuluSpace.sm),
                  ...children,
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(PazuluSpace.lg),
              children: [
                const PageTitle('Réglages', kicker: 'Apparence, langues, sources, sauvegarde'),
                const SizedBox(height: PazuluSpace.lg),
                section('Mises à jour', [
                  Row(children: [
                    Expanded(
                      child: Text(
                        app.availableUpdate != null
                            ? 'Version $appVersion · v${app.availableUpdate!.version} disponible'
                            : 'Version $appVersion${app.updateCheckedAt != null ? ' · à jour (vérifié ${relativeTime(app.updateCheckedAt!)})' : ''}',
                        style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
                      ),
                    ),
                    GhostButton(
                      label: app.availableUpdate != null ? 'Voir' : (app.checkingUpdate ? 'Recherche…' : 'Vérifier'),
                      icon: Icons.system_update_alt_rounded,
                      onPressed: app.availableUpdate != null
                          ? () => showUpdateDialog(context)
                          : (app.checkingUpdate || !app.updatesConfigured ? null : app.checkForAppUpdate),
                    ),
                  ]),
                  const SizedBox(height: PazuluSpace.md),
                  TextFormField(
                    initialValue: s.updateRepo,
                    decoration: InputDecoration(
                      labelText: 'Dépôt GitHub des versions (propriétaire/dépôt)',
                      hintText: defaultUpdateRepo.isEmpty ? 'ex. liam/pazulu-reader' : defaultUpdateRepo,
                      helperText: 'Les « Releases » de ce dépôt contiennent le ZIP Windows. Vide = dépôt officiel.',
                    ),
                    onFieldSubmitted: (v) => app.setUpdateSettings(repo: v),
                    onChanged: (v) {
                      if (v.trim().isEmpty || v.contains('/')) app.setUpdateSettings(repo: v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chercher les mises à jour automatiquement'),
                    subtitle: const Text('Au démarrage puis toutes les 6 heures. Rien n’est installé sans ton accord.'),
                    value: s.autoUpdateCheck,
                    onChanged: (v) => app.setUpdateSettings(auto: v),
                  ),
                ]),
                section('Apparence', [
                  Row(children: [
                    Expanded(child: Text('Mode', style: TextStyle(color: p.text, fontWeight: FontWeight.w800))),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('CLAIR')),
                        ButtonSegment(value: true, icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('SOMBRE')),
                      ],
                      selected: {s.darkMode},
                      onSelectionChanged: (v) => app.setAppearance(dark: v.first),
                    ),
                  ]),
                  const SizedBox(height: PazuluSpace.lg),
                  Text('Couleur d\'accent : boutons, étiquettes, barres de progression',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  const SizedBox(height: PazuluSpace.md),
                  Wrap(
                    spacing: PazuluSpace.md,
                    runSpacing: PazuluSpace.md,
                    children: [
                      for (final a in pazuluAccents)
                        _PaletteSwatch(
                          palette: paletteFor(a.$1, dark: s.darkMode),
                          selected: a.$1 == p.id,
                          onTap: () => app.setAppearance(accent: a.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: PazuluSpace.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Réduire les animations'),
                    subtitle: const Text('S\'ajoute au réglage d\'accessibilité du système.'),
                    value: s.reduceMotion,
                    onChanged: (v) => app.updateSettings((st) => st.reduceMotion = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Colonnes de couvertures'),
                    subtitle: Slider(
                      value: s.gridColumns.toDouble(),
                      min: 0,
                      max: 8,
                      divisions: 8,
                      label: s.gridColumns == 0 ? 'Auto' : '${s.gridColumns}',
                      onChanged: (v) => app.updateSettings((st) => st.gridColumns = v.round()),
                    ),
                    trailing: Tag(s.gridColumns == 0 ? 'Auto' : '${s.gridColumns}'),
                  ),
                ]),
                section('Langues de lecture', [
                  Text(
                    'Ordre de préférence pour choisir le Lecteur 1. Les langues décochées ne sont pas affichées.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  for (final l in [...langs, ..._knownLangs.where((k) => !langs.contains(k))])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: langs.contains(l),
                        onChanged: (v) => app.updateSettings((st) {
                          if (v == true) {
                            st.comicLangs = [...st.comicLangs, l];
                          } else if (st.comicLangs.length > 1) {
                            st.comicLangs = st.comicLangs.where((x) => x != l).toList();
                          }
                        }),
                      ),
                      title: Row(children: [LangBadge(l), const SizedBox(width: 10), Text(langName(l))]),
                      subtitle: langs.contains(l) ? Text('Priorité ${langs.indexOf(l) + 1}') : null,
                      trailing: langs.contains(l) && langs.indexOf(l) > 0
                          ? IconButton(
                              tooltip: 'Monter',
                              icon: const Icon(Icons.arrow_upward_rounded),
                              onPressed: () => app.updateSettings((st) {
                                final idx = st.comicLangs.indexOf(l);
                                final list = [...st.comicLangs]..removeAt(idx);
                                list.insert(idx - 1, l);
                                st.comicLangs = list;
                              }),
                            )
                          : null,
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inclure le contenu « suggestif »'),
                    subtitle: const Text('Classement MangaDex. Le contenu pour adultes reste exclu.'),
                    value: s.includeSuggestive,
                    onChanged: (v) => app.updateSettings((st) => st.includeSuggestive = v),
                  ),
                ]),
                section('Lecture', [
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Telecharger le chapitre a la lecture'),
                    subtitle: const Text(
                      'Active par defaut. La recherche et les resumes ne '
                      'telechargent aucune page. Le chapitre ouvert est '
                      'conserve en CBZ si la source le permet.'),
                    value: s.cacheOnRead,
                    onChanged: (v) => app.updateSettings(
                      (st) => st.cacheOnRead = v),
                  ),
                  const SizedBox(height: PazuluSpace.sm),
                  SegmentedButton<ReaderMode>(
                    segments: [
                      for (final m in ReaderMode.values) ButtonSegment(value: m, label: Text(m.shortLabel)),
                    ],
                    selected: {s.readerMode},
                    onSelectionChanged: (set) => app.updateSettings((st) => st.readerMode = set.first),
                  ),
                  const SizedBox(height: PazuluSpace.sm),
                  Text(
                    'Les webtoons (bande verticale) s\'ouvrent en vertical par défaut ; '
                    'le sens choisi dans le lecteur (touche M) est mémorisé par œuvre.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Double page (lecture paginée)'),
                    subtitle: const Text('Touche D dans le lecteur.'),
                    value: s.doublePage,
                    onChanged: (v) => app.updateSettings((st) => st.doublePage = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ajustement des pages'),
                    subtitle: const Text('Touche W dans le lecteur.'),
                    trailing: SegmentedButton<PageFit>(
                      segments: [
                        for (final f in PageFit.values)
                          ButtonSegment(value: f, label: Text(f.label)),
                      ],
                      selected: {s.pageFit},
                      onSelectionChanged: (set) =>
                          app.updateSettings((st) => st.pageFit = set.first),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Largeur maximale en lecture verticale'),
                    subtitle: Slider(
                      value: s.verticalMaxWidth.clamp(500.0, 1600.0),
                      min: 500,
                      max: 1600,
                      divisions: 11,
                      label: '${s.verticalMaxWidth.round()} px',
                      onChanged: (v) => app.updateSettings((st) => st.verticalMaxWidth = v),
                    ),
                    trailing: Tag('${s.verticalMaxWidth.round()} px'),
                  ),
                ]),
                section('Moteur Pazulu', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Basculement automatique entre lecteurs'),
                    subtitle: const Text('Si un lecteur échoue, Pazulu cherche le MÊME '
                        'chapitre (même numéro, même édition) sur un autre lecteur. '
                        'Jamais un autre chapitre, jamais une page payante.'),
                    value: s.autoFailover,
                    onChanged: (v) => app.updateSettings((st) => st.autoFailover = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lecture via navigateur caché (expérimental)'),
                    subtitle: const Text('Pour les rares chapitres affichés seulement en JavaScript. '
                        'Désactivé par défaut : sur Windows, cette fenêtre peut recouvrir '
                        'l\'application (écran noir). Sans elle, Pazulu passe à un autre lecteur.'),
                    value: s.browserReader,
                    onChanged: (v) => app.updateSettings((st) => st.browserReader = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sources bloquées'),
                    subtitle: s.blockedSources.isEmpty
                        ? const Text('Aucune. Bloquez une source depuis la fiche d\'une œuvre '
                            '(menu de la source) si sa langue ou sa qualité est fausse.')
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final id in s.blockedSources)
                                InputChip(
                                  label: Text(app.sourceName(id)),
                                  onDeleted: () => app.unblockSource(id),
                                  deleteButtonTooltipMessage: 'Débloquer',
                                ),
                            ]),
                          ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autoriser une autre langue en secours'),
                    subtitle: const Text('Parmi vos langues de lecture, dans leur ordre de préférence.'),
                    value: s.crossLanguageFallback,
                    onChanged: (v) => app.updateSettings((st) => st.crossLanguageFallback = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.extension_rounded, color: p.bright),
                    title: const Text('Extensions'),
                    subtitle: Text('${app.installedExtensions.where((e) => e.enabled).length} '
                        'active(s) · installer, activer, revenir à une version'),
                    onTap: () => pushPage(context, const ExtensionsPage()),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.monitor_heart_outlined, color: p.bright),
                    title: const Text('Diagnostic des sources'),
                    subtitle: const Text('État, temps de réponse, dernière erreur, '
                        '« Tester cette source », journal exportable'),
                    onTap: () => pushPage(context, const DiagnosticsPage()),
                  ),
                ]),
                section('Nouveautés', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vérifier les sorties à l\'ouverture'),
                    value: s.checkOnStartup,
                    onChanged: (v) => app.updateSettings((st) => st.checkOnStartup = v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vérification automatique'),
                    subtitle: const Text('Uniquement lorsque Pazulu Reader est ouvert. '
                        'Une confirmation provient de la source, jamais du planning.'),
                    trailing: DropdownButton<int>(
                      value: s.autoCheckMinutes,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Désactivée')),
                        DropdownMenuItem(value: 15, child: Text('15 min')),
                        DropdownMenuItem(value: 30, child: Text('30 min')),
                        DropdownMenuItem(value: 60, child: Text('1 h')),
                        DropdownMenuItem(value: 120, child: Text('2 h')),
                      ],
                      onChanged: (value) {
                        if (value != null) app.updateSettings((st) => st.autoCheckMinutes = value);
                      },
                    ),
                  ),
                ]),
                section('Hors ligne', [
                  Text(
                    '${app.downloadCount} chapitre(s) téléchargé(s) · ${(app.downloadBytes / (1024 * 1024)).toStringAsFixed(1)} Mo',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Téléchargez un chapitre MangaDex avec l\'icône de téléchargement de la fiche : il est enregistré en .cbz '
                    'et se lit sans connexion. Les fichiers .cbz / .zip déjà présents sur l\'appareil s\'importent depuis la Bibliothèque.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  if (app.downloadsPath != null && Platform.isWindows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.folder_open_rounded, color: p.bright),
                      title: const Text('Ouvrir le dossier des chapitres hors ligne'),
                      subtitle: Text(app.downloadsPath!),
                      onTap: () async {
                        final dir = Directory(app.downloadsPath!);
                        if (!await dir.exists()) await dir.create(recursive: true);
                        await Process.start('explorer.exe', [dir.path], mode: ProcessStartMode.detached);
                      },
                    ),
                ]),
                section('Sauvegarde', [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.upload_file_rounded, color: p.bright),
                    title: const Text('Exporter la bibliothèque'),
                    subtitle: const Text('Fichier .pazulu : bibliothèque, progression, réglages.'),
                    onTap: () => exportLibrary(context, app),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_rounded, color: p.bright),
                    title: const Text('Importer une sauvegarde'),
                    subtitle: const Text('Fusionne avec la bibliothèque actuelle, sans perte de progression.'),
                    onTap: () => importLibrary(context, app),
                  ),
                  if (app.dataPath != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.folder_outlined, color: p.bright),
                      title: const Text('Dossier des données'),
                      subtitle: Text(app.dataPath!),
                      trailing: IconButton(
                        tooltip: 'Copier le chemin',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () => Clipboard.setData(ClipboardData(text: app.dataPath!)),
                      ),
                    ),
                ]),
                section('À propos', [
                  const Text('Pazulu Reader $appVersion'),
                  const SizedBox(height: 4),
                  Text(
                    'Moteur de sources Pazulu 2.0. Sources : MangaDex (données et images), merci aux groupes de '
                    'traduction crédités sur chaque chapitre. Les chapitres officiels payants ne sont jamais '
                    'contournés : ils restent des liens vers l\'éditeur. Pazulu n\'affiche aucune publicité.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> exportLibrary(BuildContext context, AppState app) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(app.exportBackup()));
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter la bibliothèque',
        fileName: 'pazulu-sauvegarde-$date.pazulu',
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Sauvegarde exportée.')));
    } catch (e, st) {
      AppLog.error('Export', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Export impossible : $e')));
    }
  }

  static Future<void> importLibrary(BuildContext context, AppState app) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final file = result?.files.single;
      if (file == null) return;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) bytes = await File(file.path!).readAsBytes();
      if (bytes == null) throw const FormatException('Fichier illisible.');
      final report = app.importBackup(utf8.decode(bytes));
      messenger.showSnackBar(
        SnackBar(content: Text('Sauvegarde importée : ${report.added} ajoutée(s), ${report.updated} mise(s) à jour.')),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      AppLog.error('Import', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Import impossible : $e')));
    }
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.palette, required this.selected, required this.onTap});

  final PazuluPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Accent ${palette.name}',
      child: AnimatedRotation(
        turns: selected ? -0.012 : 0,
        duration: PazuluMotion.of(context, PazuluMotion.hover),
        child: PressableBox(
          onTap: onTap,
          shadow: selected ? 5 : 3,
          child: SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    border: Border(bottom: BorderSide(color: p.ink, width: 2.5)),
                  ),
                  alignment: Alignment.center,
                  child: selected ? Icon(Icons.check_rounded, color: palette.onAccent, size: 26) : null,
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(palette.name.toUpperCase(),
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
