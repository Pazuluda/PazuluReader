import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/log.dart';
import '../../design/theme.dart';
import '../../engine/engine_version.dart';
import '../../extensions/manifest.dart';
import '../../extensions/pack.dart';
import '../../extensions/registry.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'diagnostics_page.dart';

/// Paramètres → Moteur Pazulu → Extensions.
/// Install (.pazulusource / .pazulupack), enable/disable, roll back, remove.
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  bool _busy = false;

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _install() async {
    final app = AppScope.read(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pazulusource', 'pazulupack', 'json', 'zip'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || !mounted) return;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) bytes = await File(file.path!).readAsBytes();
    if (bytes == null) {
      _notice('Fichier illisible.');
      return;
    }
    LoadedPack pack;
    try {
      pack = app.previewExtensionPack(bytes, file.name);
    } on FormatException catch (e) {
      _notice('Extension refusée : ${e.message}');
      return;
    } catch (e) {
      _notice('Extension refusée : $e');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _InstallDialog(pack: pack),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final report = await app.installExtensionPack(pack);
      _notice('${report.installed.length} installée(s), ${report.updated.length} '
          'mise(s) à jour, ${report.skipped.length} déjà présente(s).');
    } on FormatException catch (e) {
      _notice(e.message);
    } catch (e, st) {
      AppLog.error('Installation d\'extension', e, st);
      _notice('Installation impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(InstalledExtension e) async {
    try {
      final bytes = ExtensionPackReader.write([e.manifest], name: e.manifest.name);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter l\'extension',
        fileName: '${e.manifest.id}-${e.manifest.version}.pazulupack',
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _notice('Extension exportée.');
    } catch (err) {
      _notice('Export impossible : $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.pal;
    final items = app.installedExtensions;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Extensions Pazulu'),
        actions: [
          TextButton.icon(
            onPressed: () => pushPage(context, const DiagnosticsPage()),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Diagnostic'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _install,
        icon: _busy
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded),
        label: const Text('Installer une extension'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(PazuluSpace.lg, PazuluSpace.lg,
                PazuluSpace.lg, 96),
            children: [
              Text('Moteur ${SemVer.parse(pazuluEngineVersion)} · '
                  '${items.where((e) => e.enabled).length}/${items.length} extension(s) active(s)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Une extension est un fichier de règles (JSON) : elle ne contient '
                  'aucun code exécutable, ne voit ni vos bibliothèques ni vos '
                  'fichiers, et ne peut contacter que les domaines qu\'elle déclare. '
                  'Les profils marqués « non testé » sont désactivés par défaut : '
                  'activez-les puis utilisez « Tester cette source ».',
                  style: TextStyle(color: p.muted, fontSize: 13)),
              if (app.extensionWarnings.isNotEmpty) ...[
                const SizedBox(height: PazuluSpace.md),
                Glass(
                  highlight: true,
                  child: Text(app.extensionWarnings.join('\n'),
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
              const SizedBox(height: PazuluSpace.md),
              for (final e in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: PazuluSpace.sm),
                  child: _ExtensionTile(
                    item: e,
                    onToggle: (v) => app.setExtensionEnabled(e.id, v),
                    onRollback: e.previousVersion == null
                        ? null
                        : () async {
                            final ok = await app.rollbackExtension(e.id);
                            _notice(ok
                                ? 'Retour à la version ${e.previousVersion}.'
                                : 'Version précédente introuvable.');
                          },
                    onRemove: () async {
                      final ok = await app.removeExtension(e.id);
                      _notice(ok
                          ? (e.origin == ExtensionOrigin.bundled
                              ? 'Extension intégrée désactivée et réinitialisée.'
                              : 'Extension supprimée.')
                          : 'Suppression impossible.');
                    },
                    onExport: () => _export(e),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile({required this.item, required this.onToggle,
    required this.onRemove, required this.onExport, this.onRollback});

  final InstalledExtension item;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRollback;
  final VoidCallback onRemove;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = item.manifest;
    final compatible = m.engineCompatible;
    final transportLabel = switch (m.transport) {
      ExtensionTransport.native => 'connecteur compilé',
      ExtensionTransport.html => 'HTTP/HTML',
      ExtensionTransport.browser => 'HTML + WebView2 invisible',
    };
    final levelColor = switch (m.validation) {
      ValidationLevel.verifiedLive => const Color(0xFF4ADE80),
      ValidationLevel.verifiedFixtureOnly => p.bright,
      ValidationLevel.implementedUntested => const Color(0xFFFBBF24),
      ValidationLevel.metadataOnly => p.muted,
      ValidationLevel.unsupported => const Color(0xFFF87171),
    };
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(switch (m.transport) {
                ExtensionTransport.native => Icons.memory_rounded,
                ExtensionTransport.html => Icons.code_rounded,
                ExtensionTransport.browser => Icons.web_rounded,
              }, color: p.bright),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.name}  ${m.version}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${m.hosts.join(', ')} · '
                        '${m.languages.map((l) => l.toUpperCase()).join('/')} · $transportLabel',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: item.enabled && compatible,
                onChanged: compatible ? onToggle : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag(m.validation.code, color: levelColor),
              Tag(item.origin == ExtensionOrigin.bundled ? 'Intégrée' : 'Installée',
                  icon: item.origin == ExtensionOrigin.bundled
                      ? Icons.verified_user_outlined : Icons.folder_open_outlined),
              Tag(item.publisher),
              if (!compatible)
                Tag('Moteur ${m.minimumEngineVersion} requis',
                    color: const Color(0xFFF87171)),
              if (item.origin == ExtensionOrigin.userFile && !item.signed)
                const Tag('Non signée', color: Color(0xFFFBBF24),
                    icon: Icons.warning_amber_rounded),
            ],
          ),
          if (m.notes != null) ...[
            const SizedBox(height: 8),
            Text(m.notes!, style: TextStyle(color: p.muted, fontSize: 12)),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              if (onRollback != null)
                TextButton.icon(
                  onPressed: onRollback,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: Text('Revenir à ${item.previousVersion}'),
                ),
              TextButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Exporter'),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(item.origin == ExtensionOrigin.bundled
                    ? 'Réinitialiser' : 'Supprimer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstallDialog extends StatelessWidget {
  const _InstallDialog({required this.pack});

  final LoadedPack pack;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = pack.verification;
    return AlertDialog(
      title: Text(pack.name ?? 'Installer une extension'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in pack.manifests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.extension_rounded),
                  title: Text('${m.name} ${m.version}'),
                  subtitle: Text('Domaines : ${m.hosts.join(', ')}\n'
                      'Niveau : ${m.validation.label}'),
                ),
              const Divider(),
              Text('Intégrité : ${v.integrityOk ? 'empreintes SHA-256 conformes' : 'NON CONFORME'}'),
              Text('Origine déclarée : ${v.publisher}'),
              Text('Signature : ${v.signed ? 'vérifiée' : 'non vérifiée'}'),
              const SizedBox(height: 8),
              for (final w in v.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $w', style: TextStyle(color: p.muted, fontSize: 12)),
                ),
              Text('SHA-256 du fichier : ${pack.sha256.substring(0, 16)}…',
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler')),
        FilledButton(onPressed: v.integrityOk ? () => Navigator.of(context).pop(true) : null,
            child: const Text('Installer')),
      ],
    );
  }
}
