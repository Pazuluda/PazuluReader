import 'chapters.dart';

/// Facts observed in connected catalogues. This is NOT an estimate of the
/// number of published chapters or a guarantee of completeness.
class LanguageInventory {
  const LanguageInventory({
    required this.language,
    required this.listed,
    required this.readable,
    required this.externalOnly,
    required this.sourceCount,
    this.latestLabel,
  });

  final String language;
  /// Distinct canonical chapter numbers visible in at least one source.
  final int listed;
  /// Chapters with at least one native/offline variant.
  final int readable;
  /// Chapters only linked to an official/external reader.
  final int externalOnly;
  final int sourceCount;
  final String? latestLabel;
}

/// Summarise observed availability without filling numeric gaps: a chapter
/// numbered 1197 does not imply that 1196 earlier chapters were fetched.
LanguageInventory inventoryForLanguage(
    List<ChapterGroup> groups, String language) {
  var listed = 0;
  var readable = 0;
  var externalOnly = 0;
  final sources = <String>{};
  String? latestLabel;
  for (final g in groups) {
    final versions = g.variants.where((v) =>
        v.lang == language || (v.lang == 'local' && language == 'local')).toList();
    if (versions.isEmpty) continue;
    listed++;
    latestLabel = g.key.label;
    sources.addAll(versions.map((v) => v.sourceId));
    if (versions.any((v) => !v.isExternal)) {
      readable++;
    } else {
      externalOnly++;
    }
  }
  return LanguageInventory(
    language: language,
    listed: listed,
    readable: readable,
    externalOnly: externalOnly,
    sourceCount: sources.length,
    latestLabel: latestLabel,
  );
}
