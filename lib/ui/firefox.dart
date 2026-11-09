import 'dart:io';

import 'package:flutter/material.dart';

import 'external_link.dart';

/// Firefox on this PC (standard installs), or null.
String? firefoxPath() {
  if (!Platform.isWindows) return null;
  final env = Platform.environment;
  final candidates = [
    for (final base in [env['ProgramFiles'], env['ProgramFiles(x86)'], env['ProgramW6432'], env['LOCALAPPDATA']])
      if (base != null && base.isNotEmpty) '$base\\Mozilla Firefox\\firefox.exe',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

/// Opens [url] in Firefox (where « Roll With Your Friends » is installed).
/// Without Firefox, the default browser is used and the user is told.
Future<bool> openInFirefox(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    messenger?.showSnackBar(const SnackBar(content: Text('Lien invalide, ouverture refusée.')));
    return false;
  }
  final exe = firefoxPath();
  if (exe != null) {
    try {
      await Process.start(exe, ['-new-tab', uri.toString()], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      // falls back to the default browser below
    }
  }
  messenger?.showSnackBar(const SnackBar(
      content: Text('Firefox introuvable : ouverture dans le navigateur par défaut.')));
  if (context.mounted) await openOfficialLink(context, uri.toString());
  return false;
}
