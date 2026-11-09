import 'models.dart';

/// A catalogue entry is only a claim that a source lists a chapter.
/// Its presence does not imply access to the pages or completeness of a series.
enum CatalogueCheckState { checked, empty, failed, unsupported }

class CatalogueCheck {
  const CatalogueCheck({
    required this.sourceId,
    required this.name,
    required this.state,
    required this.observed,
    required this.readable,
    this.detail,
    this.retained = 0,
  });

  final String sourceId;
  final String name;
  final CatalogueCheckState state;
  final int observed;
  final int readable;
  final int retained;
  final String? detail;

  bool get confirmed => state == CatalogueCheckState.checked ||
      state == CatalogueCheckState.empty;
}

/// On refresh, a failed site must not erase previously observed chapters.
/// Retained variants are stale, never counted as newly confirmed by the audit.
/// A successfully fetched empty list, on the other hand, replaces old entries.
List<SourceChapter> mergeObservedChapters({
  required List<SourceChapter> previous,
  required Map<String, List<SourceChapter>> successful,
  required Set<String> failed,
  required Iterable<SourceChapter> local,
}) {
  final merged = <String, SourceChapter>{};
  void add(SourceChapter c) {
    merged['${c.sourceId}:${c.chapterId}'] = c;
  }
  for (final batch in successful.values) {
    for (final chapter in batch) { add(chapter); }
  }
  for (final chapter in previous) {
    if (failed.contains(chapter.sourceId) &&
        !successful.containsKey(chapter.sourceId)) {
      add(chapter);
    }
  }
  for (final chapter in local) { add(chapter); }
  return merged.values.toList();
}
