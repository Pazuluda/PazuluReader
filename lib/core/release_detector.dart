import '../engine/identity/listing_guard.dart';
import 'models.dart';

/// Détection des sorties par œuvre, source, langue et numéro canonique.
/// Aucun chapitre n'est inventé depuis un calendrier : seul le connecteur
/// ayant réellement observé une publication peut produire un événement.
class ReleaseDetector {
  static const int historyLimit = 1000;

  /// Modifie l'historique de [entry] et retourne les nouveautés confirmées.
  /// Au premier passage on constitue une référence sans notifier tout le
  /// catalogue historique. Les anciennes bibliothèques migrent en utilisant
  /// latestKnown pour ne pas signaler les anciens chapitres.
  /// A release older than this is history, never a « new » chapter.
  static const Duration freshness = Duration(days: 14);

  /// More undated chapters than this at once = a backfill (new source, list
  /// that grew), not real releases.
  static const int burstLimit = 5;

  /// Every source is checked the same way (no source is a reference):
  /// a « chapter 3861 » in a 200-chapter series is another work's chapter.

  static bool plausible(double? number, double? reference) {
    if (number == null || reference == null) return true;
    return number <= reference * 1.3 + 15;
  }

  /// Completed / cancelled series (any source's status label).
  static bool finished(WorkInfo work) {
    final s = (work.publicationStatus ?? '').toLowerCase();
    return s.contains('termin') || s.contains('annul') || s.contains('complet') ||
        s.contains('finished') || s.contains('cancel');
  }

  static List<SourceChapter> observe(
    LibraryEntry entry,
    String sourceId,
    Iterable<SourceChapter> chapters, {
    required List<String> langs,
    DateTime? now,
    bool firstObservationIsBaseline = false,
  }) {
    final currentTime = now ?? DateTime.now();
    final usable = chapters.where((c) => c.sourceId == sourceId &&
        langs.contains(c.lang) &&
        (c.publishedAt == null || !c.publishedAt!.isAfter(currentTime))).toList();
    final detected = <SourceChapter>[];
    for (final lang in langs.toSet()) {
      final bucket = '$sourceId|$lang';
      final prior = entry.observedChapters[bucket];
      final previous = (prior ?? const <String>[]).toSet();
      double? priorMax;
      for (final id in previous) {
        final n = double.tryParse(id);
        if (n != null && (priorMax == null || n > priorMax)) priorMax = n;
      }
      // What the OTHER sources already listed in this language: a chapter
      // they had before is not a release because one more site shows it.
      final elsewhere = <String>{};
      for (final b in entry.observedChapters.entries) {
        if (b.key == bucket || !b.key.endsWith('|$lang')) continue;
        elsewhere.addAll(b.value);
      }
      final legacy = entry.latestKnown[lang];
      final reference = [priorMax, legacy].whereType<double>().fold<double?>(
          null, (m, v) => m == null || v > m ? v : m);
      final uniqueNow = <String, SourceChapter>{};
      final inLang = usable.where((c) => c.lang == lang).toList();
      // A complete, continuous list (1 … 330) is its own proof.
      final complete = ListingGuard.dense(inLang);
      for (final c in inLang) {
        if (!complete && !plausible(c.key.number, reference)) continue;
        uniqueNow.putIfAbsent(c.key.id, () => c);
      }

      final candidates = <SourceChapter>[];
      for (final c in uniqueNow.values) {
        final knownPreviously = prior != null && previous.contains(c.key.id);
        final newVersusLegacy = legacy != null &&
            c.key.number != null && c.key.number! > legacy;
        if (knownPreviously ||
            !(prior != null || (!firstObservationIsBaseline && newVersusLegacy))) {
          continue;
        }
        final published = c.publishedAt;
        if (published != null && currentTime.difference(published) > freshness) continue;
        if (elsewhere.contains(c.key.id)) continue;
        // A finished series gets no « new » chapter up to its last one.
        if (finished(entry.work) && published == null) continue;
        candidates.add(c);
      }
      final undated = candidates.where((c) => c.publishedAt == null).length;
      if (undated > burstLimit) {
        candidates.removeWhere((c) => c.publishedAt == null);
      }
      detected.addAll(candidates);
      // Conserve les chapitres vus précédemment, même s'ils disparaissent du
      // dernier flux (un simple flux limité ne doit pas créer de doublons).
      final accumulated = <String>{...previous, ...uniqueNow.keys}.toList();
      entry.observedChapters[bucket] = accumulated.length <= historyLimit
          ? accumulated
          : accumulated.sublist(accumulated.length - historyLimit);
      for (final c in uniqueNow.values) {
        final n = c.key.number;
        if (n != null && (entry.latestKnown[lang] == null || n > entry.latestKnown[lang]!)) {
          entry.latestKnown[lang] = n;
        }
      }
    }
    return detected;
  }
}


/// Cleans notifications produced by older versions: backfill bursts (dozens
/// of old chapters « released » at the same minute) and chapters of other
/// works attached by a wrong web match. Also repairs [LibraryEntry.latestKnown].
class UpdateHygiene {
  /// Highest chapter number the sources agree on: the maximum of every
  /// bucket (all sources are peers) once a bucket's isolated far-away
  /// numbers (another series mixed in) are cut off, and the reading progress.
  static double? trustedReference(LibraryEntry e) {
    double? best;
    void take(double n) {
      if (best == null || n > best!) best = n;
    }
    for (final b in e.observedChapters.values) {
      final numbers = [for (final id in b) if (double.tryParse(id) case final double n) n]..sort();
      if (numbers.isEmpty) continue;
      var cleanMax = numbers.first;
      for (var i = 1; i < numbers.length; i++) {
        final limit = numbers[i - 1] * 0.35 < 80 ? 80 : numbers[i - 1] * 0.35;
        if (numbers[i] - numbers[i - 1] > limit) break;
        cleanMax = numbers[i];
      }
      take(cleanMax);
    }
    for (final id in e.progress.readKeys) {
      final n = double.tryParse(id);
      if (n != null) take(n);
    }
    return best;
  }

  /// Returns the number of removed notifications.
  static int clean(List<UpdateItem> updates, Map<String, LibraryEntry> entries) {
    final before = updates.length;
    // 1. Bursts: > burstLimit undated items of one work found within 3 min.
    final byWork = <String, List<UpdateItem>>{};
    for (final u in updates) {
      if (u.publishedAt == null) byWork.putIfAbsent(u.workId, () => []).add(u);
    }
    final burst = <UpdateItem>{};
    for (final list in byWork.values) {
      list.sort((a, b) => a.foundAt.compareTo(b.foundAt));
      var start = 0;
      for (var i = 0; i <= list.length; i++) {
        final cut = i == list.length ||
            list[i].foundAt.difference(list[start].foundAt) > const Duration(minutes: 3);
        if (cut) {
          if (i - start > ReleaseDetector.burstLimit) burst.addAll(list.sublist(start, i));
          start = i;
        }
      }
    }
    // 2. Implausible numbers versus the trusted reference.
    final refs = <String, double?>{
      for (final e in entries.values) e.work.id: trustedReference(e),
    };
    updates.removeWhere((u) {
      if (burst.contains(u)) return true;
      final e = entries[u.workId];
      if (e != null && ReleaseDetector.finished(e.work) && u.siteId == null &&
          (u.publishedAt == null ||
              u.foundAt.difference(u.publishedAt!) > ReleaseDetector.freshness)) {
        return true;
      }
      final ref = refs[u.workId];
      return !ReleaseDetector.plausible(u.key.number, ref);
    });
    // 3. latestKnown polluted by such chapters.
    for (final e in entries.values) {
      final ref = refs[e.work.id];
      if (ref == null) continue;
      for (final lang in e.latestKnown.keys.toList()) {
        if (!ReleaseDetector.plausible(e.latestKnown[lang], ref)) e.latestKnown[lang] = ref;
      }
    }
    return before - updates.length;
  }
}
