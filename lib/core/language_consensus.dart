import 'models.dart';

/// Language confirmation by the sources themselves (no source is trusted
/// more than another). A chapter in a language L is « unconfirmed » when a
/// single source offers it, AHEAD of every other source of that language,
/// while the chapter already exists in another language: typical of a site
/// that labels the English release « VF » before any French team.
/// It stays readable (« FR ? ») but is not announced as a FR release until a
/// second source of that language lists it.
class LanguageConsensus {
  static Set<String> unconfirmed(Iterable<SourceChapter> chapters) {
    final readable = [
      for (final c in chapters)
        if (!c.isExternal && c.key.number != null) c,
    ];
    final langsOfKey = <String, Set<String>>{};
    for (final c in readable) {
      langsOfKey.putIfAbsent(c.key.id, () => {}).add(c.lang);
    }
    final out = <String>{};
    final byLang = <String, Map<String, List<SourceChapter>>>{};
    for (final c in readable) {
      byLang.putIfAbsent(c.lang, () => {}).putIfAbsent(c.sourceId, () => []).add(c);
    }
    for (final entry in byLang.entries) {
      final lang = entry.key;
      final perSource = entry.value;
      if (perSource.length < 2) continue;
      final holders = <String, Set<String>>{};
      for (final list in perSource.values) {
        for (final c in list) {
          holders.putIfAbsent(c.key.id, () => {}).add(c.sourceId);
        }
      }
      for (final s in perSource.entries) {
        double? maxOthers;
        for (final o in perSource.entries) {
          if (o.key == s.key) continue;
          for (final c in o.value) {
            if (maxOthers == null || c.key.number! > maxOthers) maxOthers = c.key.number;
          }
        }
        if (maxOthers == null) continue;
        for (final c in s.value) {
          final alone = (holders[c.key.id]?.length ?? 0) < 2;
          final otherLang = (langsOfKey[c.key.id] ?? const {}).any((l) => l != lang);
          if (alone && otherLang && c.key.number! > maxOthers) out.add(c.chapterId);
        }
      }
    }
    return out;
  }

  /// Same rule on the release-detection memory (buckets « source|lang »).
  static bool aheadOfPeers(LibraryEntry e, String sourceId, String lang, String keyId) {
    final n = double.tryParse(keyId);
    if (n == null) return false;
    double? maxOthers;
    var otherLang = false;
    for (final b in e.observedChapters.entries) {
      final parts = b.key.split('|');
      if (parts.length != 2) continue;
      if (parts[1] != lang) {
        if (b.value.contains(keyId)) otherLang = true;
        continue;
      }
      if (parts[0] == sourceId) continue;
      if (b.value.contains(keyId)) return false; // another source has it
      for (final id in b.value) {
        final v = double.tryParse(id);
        if (v != null && (maxOthers == null || v > maxOthers)) maxOthers = v;
      }
    }
    return maxOthers != null && otherLang && n > maxOthers;
  }

  /// Startup cleaning of older notifications (the source is not stored in
  /// them): a language release held by a single source, ahead of all others.
  static bool heldBySingleSourceAhead(LibraryEntry e, String lang, String keyId) {
    final holders = <String>[];
    for (final b in e.observedChapters.entries) {
      final parts = b.key.split('|');
      if (parts.length == 2 && parts[1] == lang && b.value.contains(keyId)) holders.add(parts[0]);
    }
    if (holders.length != 1) return false;
    return LanguageConsensus.aheadOfPeers(e, holders.single, lang, keyId);
  }

  /// Any language: a chapter only [sourceId] has, above the last chapter of
  /// at least 3 other sources of that language (a site that numbers
  /// differently, a re-upload). Not announced until a 2nd site confirms.
  static bool singleSourceAhead(LibraryEntry e, String sourceId, String lang, String keyId) {
    final n = double.tryParse(keyId);
    if (n == null) return false;
    var lower = 0;
    for (final b in e.observedChapters.entries) {
      final parts = b.key.split('|');
      if (parts.length != 2 || parts[1] != lang || parts[0] == sourceId) continue;
      if (b.value.contains(keyId)) return false;
      double? top;
      for (final id in b.value) {
        final v = double.tryParse(id);
        if (v != null && (top == null || v > top)) top = v;
      }
      if (top != null && top < n && b.value.length >= 10) lower++;
    }
    return lower >= 3;
  }
}
