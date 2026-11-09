import '../../core/models.dart';
import '../../core/source.dart';
import '../availability.dart';
import '../diagnostics/connector_health.dart';
import '../http/engine_http.dart';
import '../identity/canonical_chapter.dart';
import 'chapter_resolver.dart';
import 'circuit_breaker.dart';

enum RouteStepState {
  checking,
  confirmed,
  unavailable,
  restricted,
  partial,
  invalid,
  needsBrowser,
  skippedDifferentChapter,
  skippedNeedsConfirmation,
  skippedLanguage,
  skippedExternal,
  skippedNoConnector,
  skippedPaused,
}

/// One line of the reader status panel ("Source 2 : vérification des pages").
class RouteStep {
  const RouteStep(this.index, this.chapter, this.state, this.message);

  final int index;
  final SourceChapter chapter;
  final RouteStepState state;
  final String message;

  String get line => 'Lecteur ${index + 1} (${chapter.group} · '
      '${chapter.lang.toUpperCase()}) : $message';
}

class RouteOutcome {
  const RouteOutcome({
    required this.steps,
    this.selectedIndex,
    this.pages,
    this.needsBrowser = false,
    this.confirmationCandidates = const [],
    this.lastError,
  });

  final List<RouteStep> steps;
  final int? selectedIndex;
  final ChapterPages? pages;

  /// The selected candidate must be rendered by the hidden WebView2.
  final bool needsBrowser;

  /// Same number but uncertain identity: shown to the user, never auto-used.
  final List<int> confirmationCandidates;
  final Object? lastError;

  bool get success => selectedIndex != null && (pages?.readable ?? needsBrowser);
}

typedef SourceLookup = ContentSource? Function(String sourceId);

/// Smart Source Router: tries the ranked readers of ONE canonical chapter,
/// validates real pages, and falls back only to a true equivalent.
///
/// Never: another chapter number (115.1 → 115.2), another edition (novel ↔
/// manga), an external/paywalled link, a language the user excluded, or a
/// domain whose circuit is open.
class SmartSourceRouter {
  SmartSourceRouter({
    required this.resolver,
    required this.breaker,
    required this.health,
  });

  final ChapterResolver resolver;
  final CircuitBreaker breaker;
  final ConnectorHealthStore health;

  Future<RouteOutcome> route({
    required SourceChapter requested,
    required List<SourceChapter> candidates,
    required SourceLookup lookup,
    int startIndex = 0,
    Set<int> exclude = const {},
    bool autoFallback = true,
    bool allowOtherLanguages = true,
    List<String> preferredLanguages = const [],
    String? edition,
    bool Function(SourceChapter chapter)? isOffline,
    void Function(RouteStep step)? onStep,
    CancelToken? cancel,
    Set<int> userConfirmed = const {},
  }) async {
    final steps = <RouteStep>[];
    final confirmations = <int>[];
    final target = CanonicalChapter.of(requested, edition: edition);
    Object? lastError;

    void emit(RouteStep step) {
      steps.add(step);
      onStep?.call(step);
    }

    final order = <int>[
      if (startIndex >= 0 && startIndex < candidates.length) startIndex,
      for (var i = 0; i < candidates.length; i++) if (i != startIndex) i,
    ];
    var attempted = 0;
    for (final i in order) {
      if (cancel?.isCancelled ?? false) break;
      if (exclude.contains(i)) continue;
      final c = candidates[i];
      final isRequested = c.sourceId == requested.sourceId && c.chapterId == requested.chapterId;
      if (!isRequested) {
        final eq = target.compare(CanonicalChapter.of(c, edition: edition));
        if (eq == Equivalence.different) {
          emit(RouteStep(i, c, RouteStepState.skippedDifferentChapter,
              'chapitre différent (${c.key.longLabel}), ignoré'));
          continue;
        }
        if (eq == Equivalence.needsConfirmation && !userConfirmed.contains(i)) {
          confirmations.add(i);
          emit(RouteStep(i, c, RouteStepState.skippedNeedsConfirmation,
              'édition incertaine : confirmation nécessaire'));
          continue;
        }
        if (!allowOtherLanguages && preferredLanguages.isNotEmpty &&
            !preferredLanguages.contains(c.lang)) {
          emit(RouteStep(i, c, RouteStepState.skippedLanguage, 'langue exclue des préférences'));
          continue;
        }
      }
      if (c.isExternal) {
        emit(RouteStep(i, c, RouteStepState.skippedExternal,
            'lien éditeur externe, pas de pages intégrables'));
        continue;
      }
      if (isOffline?.call(c) ?? false) {
        // Offline copies are validated by the reader from local bytes.
        emit(RouteStep(i, c, RouteStepState.confirmed, 'copie hors ligne disponible'));
        return RouteOutcome(steps: steps, selectedIndex: i,
            confirmationCandidates: confirmations);
      }
      final source = lookup(c.sourceId);
      if (source == null) {
        emit(RouteStep(i, c, RouteStepState.skippedNoConnector, 'aucun connecteur actif'));
        continue;
      }
      if (attempted > 0 && !autoFallback) break;
      attempted++;
      emit(RouteStep(i, c, RouteStepState.checking, 'vérification des pages…'));
      final watch = Stopwatch()..start();
      try {
        final pages = await resolver.resolve(c, source, cancel: cancel);
        if (pages.readable) {
          health.of(c.sourceId).recordSuccess(watch.elapsed);
          emit(RouteStep(i, c, RouteStepState.confirmed,
              'chapitre confirmé (${pages.summary})'));
          return RouteOutcome(steps: steps, selectedIndex: i, pages: pages,
              confirmationCandidates: confirmations);
        }
        final state = switch (pages.completeness) {
          PageCompleteness.partial => RouteStepState.partial,
          PageCompleteness.restricted => RouteStepState.restricted,
          _ => RouteStepState.invalid,
        };
        final detail = pages.issues.where((x) => x.fatal).take(2).join(' ; ');
        health.of(c.sourceId).recordFailure('${pages.completeness.label}: $detail');
        lastError = ChapterValidationException(pages.summary, result: pages);
        emit(RouteStep(i, c, state, '${pages.summary}${detail.isEmpty ? '' : ' — $detail'}'));
      } on NeedsBrowserRendering {
        emit(RouteStep(i, c, RouteStepState.needsBrowser,
            'rendu JavaScript invisible nécessaire'));
        return RouteOutcome(steps: steps, selectedIndex: i, needsBrowser: true,
            confirmationCandidates: confirmations);
      } on ChapterRestrictedException catch (e) {
        lastError = e;
        health.of(c.sourceId).recordFailure(e.message);
        emit(RouteStep(i, c, e.kind == AccessKind.rateLimited
            ? RouteStepState.skippedPaused : RouteStepState.restricted, e.kind.label));
      } on RequestCancelled {
        break;
      } catch (e) {
        lastError = e;
        health.of(c.sourceId).recordFailure('$e');
        emit(RouteStep(i, c, RouteStepState.unavailable, 'indisponible ($e)'));
      }
    }
    return RouteOutcome(steps: steps, confirmationCandidates: confirmations,
        lastError: lastError);
  }
}

/// Orders readers inside the tiers decided by [SourceRouting]: preferred
/// language first, then real reliability, latency and known page count.
class SourceRanker {
  const SourceRanker(this.health);

  final ConnectorHealthStore health;

  double score(SourceChapter c, {String? preferredSourceId}) {
    final stats = health.stats[c.sourceId];
    var s = (stats?.reliability ?? 0.6) * 10;
    final latency = stats?.avgLatencyMs;
    if (latency != null) s -= (latency / 4000).clamp(0, 2);
    if (c.pages > 0) s += 0.5; // announced page count ⇒ verifiable completeness
    if (preferredSourceId != null && c.sourceId == preferredSourceId) s += 3;
    return s;
  }

  /// Stable re-order: [tier] and [langRank] dominate, health refines.
  List<SourceChapter> refine(List<SourceChapter> ranked, {
    required int Function(SourceChapter c) tier,
    required int Function(SourceChapter c) langRank,
    String? preferredSourceId,
  }) {
    final indexed = [for (var i = 0; i < ranked.length; i++) (i, ranked[i])];
    indexed.sort((a, b) {
      final t = tier(a.$2).compareTo(tier(b.$2));
      if (t != 0) return t;
      final l = langRank(a.$2).compareTo(langRank(b.$2));
      if (l != 0) return l;
      final s = score(b.$2, preferredSourceId: preferredSourceId)
          .compareTo(score(a.$2, preferredSourceId: preferredSourceId));
      if (s.abs() > 0) return s;
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}

/// Re-exported for convenience in the UI layer.
typedef BreakerSnapshot = BreakerStatus;
