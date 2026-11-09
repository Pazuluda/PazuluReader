import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../crunchyroll_player_page.dart';

/// Opens a Crunchyroll episode (or series) inside Pazulu: official site and
/// player in the built-in browser, with the user's own account.
Future<void> watchOnCrunchyroll(BuildContext context, String url,
        {String title = 'Crunchyroll', int? episode, ValueChanged<String>? onEpisodeUrl,
        Map<String, Object?> hints = const {}, ValueChanged<int>? onCrunchyrollNumber}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CrunchyrollPlayerPage(url: url, title: title, episode: episode,
            onEpisodeUrl: onEpisodeUrl, hints: hints, onCrunchyrollNumber: onCrunchyrollNumber)));

/// « Regarder ensemble » : the episode in Pazulu with « Roll With Your
/// Friends » running in the page; the room is created as soon as the
/// player is ready, the link to share is shown at the top.
Future<void> watchTogether(BuildContext context, String url,
        {String title = 'Crunchyroll', int? episode, ValueChanged<String>? onEpisodeUrl,
        Map<String, Object?> hints = const {}}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CrunchyrollPlayerPage(url: url, title: title, episode: episode,
            onEpisodeUrl: onEpisodeUrl, together: true, hints: hints)));

/// « Rejoindre une soirée » : paste a friend's link (Pazulu or Firefox).
Future<void> joinPartyDialog(BuildContext context) async {
  final field = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('REJOINDRE UNE SOIRÉE'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://www.crunchyroll.com/…?rollTogetherRoom=…'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, field.text.trim()), child: const Text('Rejoindre')),
      ],
    ),
  );
  field.dispose();
  if (url == null || url.isEmpty || !context.mounted) return;
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  final ok = uri != null && uri.scheme == 'https' &&
      (host == 'crunchyroll.com' || host.endsWith('.crunchyroll.com')) &&
      (uri.queryParameters['rollTogetherRoom'] ?? '').isNotEmpty;
  if (!ok) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Ce n’est pas un lien de soirée Crunchyroll (« rollTogetherRoom= » manquant).')));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CrunchyrollPlayerPage(url: url, title: 'Soirée Crunchyroll')));
}

/// The two buttons (Kiosque style) used on cards and on the anime page.
class CrunchyrollButtons extends StatelessWidget {
  const CrunchyrollButtons({super.key, required this.url, required this.title, this.episode,
      this.compact = false, this.onEpisodeUrl, this.hints = const {}});

  final Map<String, Object?> hints;

  final String url;
  final String title;
  final ValueChanged<String>? onEpisodeUrl;
  final int? episode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = episode == null ? 'Regarder sur Crunchyroll' : 'Regarder l’ép. $episode';
    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _MiniButton(icon: Icons.play_arrow_rounded, tooltip: '$label (Crunchyroll)',
            accent: true, onTap: () => watchOnCrunchyroll(context, url, title: title, episode: episode, onEpisodeUrl: onEpisodeUrl, hints: hints)),
        const SizedBox(width: 4),
        _MiniButton(icon: Icons.groups_rounded, tooltip: 'Regarder ensemble (Roll With Your Friends)',
            onTap: () => watchTogether(context, url, title: title, episode: episode, onEpisodeUrl: onEpisodeUrl, hints: hints)),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
        onPressed: () => watchOnCrunchyroll(context, url, title: title, episode: episode, onEpisodeUrl: onEpisodeUrl, hints: hints),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(label),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => watchTogether(context, url, title: title, episode: episode, onEpisodeUrl: onEpisodeUrl, hints: hints),
        icon: const Icon(Icons.groups_rounded, size: 20),
        label: const Text('Regarder ensemble'),
      ),
    ]);
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.tooltip, required this.onTap, this.accent = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: accent ? p.accent : p.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: p.ink, width: 2)),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: accent ? p.onAccent : p.text),
          ),
        ),
      ),
    );
  }
}
