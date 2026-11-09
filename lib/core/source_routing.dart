import 'models.dart';

/// Sélection factuelle des versions, indépendante des widgets.
/// Un lien HTML ou éditeur ne constitue jamais des pages disponibles.
enum SourceAccess { offline, native, external, unsupported, temporarilyUnavailable }

class SourceRouting {
  const SourceRouting._();

  static SourceAccess access(SourceChapter chapter, {
    required bool Function(String chapterId) isCached,
    required bool Function(String sourceId) hasConnector,
    required bool Function(String chapterId) recentlyFailed,
  }) {
    if (isCached(chapter.chapterId)) return SourceAccess.offline;
    if (chapter.isExternal) return SourceAccess.external;
    if (!hasConnector(chapter.sourceId)) return SourceAccess.unsupported;
    if (recentlyFailed(chapter.chapterId)) return SourceAccess.temporarilyUnavailable;
    return SourceAccess.native;
  }

  /// Priority: cached copy, usable native reader, temporary failure,
  /// catalogue-only record and external editor link. Stable within a tier.
  static List<SourceChapter> rank(List<SourceChapter> candidates, {
    required List<String> preferredLanguages,
    required bool Function(String chapterId) isCached,
    required bool Function(String sourceId) hasConnector,
    required bool Function(String chapterId) recentlyFailed,
  }) {
    int tier(SourceChapter c) => switch (access(c,
      isCached: isCached, hasConnector: hasConnector,
      recentlyFailed: recentlyFailed)) {
        SourceAccess.offline => 0,
        SourceAccess.native => 1,
        SourceAccess.temporarilyUnavailable => 2,
        SourceAccess.unsupported => 3,
        SourceAccess.external => 4,
      };
    int languageRank(SourceChapter c) {
      final rank = preferredLanguages.indexOf(c.lang);
      return rank < 0 ? 99 : rank;
    }
    final sorted = [...candidates];
    final originalOrder = <SourceChapter, int>{
      for (var i = 0; i < candidates.length; i++) candidates[i]: i,
    };
    sorted.sort((a, b) {
      final byTier = tier(a).compareTo(tier(b));
      if (byTier != 0) return byTier;
      final byLang = languageRank(a).compareTo(languageRank(b));
      if (byLang != 0) return byLang;
      // Preserve the preferred group/source order passed by rankVariants.
      return originalOrder[a]!.compareTo(originalOrder[b]!);
    });
    return sorted;
  }

  static bool canOpenInPazulu(SourceChapter chapter, {
    required bool Function(String chapterId) isCached,
    required bool Function(String sourceId) hasConnector,
    required bool Function(String chapterId) recentlyFailed,
  }) {
    final kind = access(chapter, isCached: isCached,
      hasConnector: hasConnector, recentlyFailed: recentlyFailed);
    return kind == SourceAccess.offline || kind == SourceAccess.native;
  }
}
