import 'dart:io';

import 'models.dart';
import 'source_health.dart' show isNonPublicIpAddress;
import 'source.dart';

/// Common checks for every installed native reader. A list of image URLs is
/// not a successful read if it is empty, repeated or shorter than a known
/// chapter page count. No cross-site or guessed URLs are produced here.
class ReaderFailover {
  const ReaderFailover._();

  static void validatePages(SourceChapter chapter, List<PageRef> pages,
      {bool offline = false}) {
    if (pages.isEmpty) {
      throw const SourceException('La source n a retourne aucune page lisible.');
    }
    if (chapter.pages > 0 && pages.length < chapter.pages) {
      throw SourceException('Chapitre incomplet : ${pages.length}/${chapter.pages} '
          'pages annoncees par ${chapter.group}.');
    }
    final seen = <String>{};
    for (final page in pages) {
      final raw = page.url.trim();
      if (!seen.add(raw)) {
        throw const SourceException('Pages dupliquees : chapitre non fiable.');
      }
      if (offline) {
        if (!RegExp(r'^hors-ligne:\d+$').hasMatch(raw)) {
          throw const SourceException('Page locale non reconnue.');
        }
      } else {
        final uri = Uri.tryParse(raw);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
            uri.hasPort || uri.userInfo.isNotEmpty ||
          _isLocalHost(uri.host)) {
          throw const SourceException('URL de page invalide ou non securisee.');
        }
      }
    }
  }

  static bool _isLocalHost(String hostname) {
    final host = hostname.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || host.endsWith('.internal')) return true;
    final parsed = InternetAddress.tryParse(host);
    return parsed != null && isNonPublicIpAddress(parsed);
  }

  /// The variants are already ordered by the reader preferences. We only
  /// switch to another *real* connector or an offline copy, never a catalogue
  /// entry, an unsupported site or a publisher's external link.
  static int? next(List<SourceChapter> variants, {
    required int current,
    required Set<int> failed,
    required bool Function(SourceChapter chapter) canRead,
  }) {
    for (var i = 0; i < variants.length; i++) {
      if (i != current && !failed.contains(i) && canRead(variants[i])) {
        return i;
      }
    }
    return null;
  }
}
