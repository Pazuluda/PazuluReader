import 'dart:io';

import 'package:flutter/material.dart';

/// Opens an official page (Crunchyroll, ADN, Netflix, AniList…) in the
/// user's default browser. Only plain http(s) links are accepted: nothing is
/// executed, and Pazulu never embeds or extracts the video itself.
Future<void> openOfficialLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok = uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!ok) {
    messenger?.showSnackBar(const SnackBar(content: Text('Lien invalide, ouverture refusée.')));
    return;
  }
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', uri.toString()],
          mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [uri.toString()], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [uri.toString()], mode: ProcessStartMode.detached);
    }
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text('Impossible d\'ouvrir ${uri.host}.')));
  }
}
