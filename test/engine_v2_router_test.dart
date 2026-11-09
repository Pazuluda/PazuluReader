import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source.dart';
import 'package:pazulu_reader/engine/availability.dart';
import 'package:pazulu_reader/engine/diagnostics/connector_health.dart';
import 'package:pazulu_reader/engine/diagnostics/engine_log.dart';
import 'package:pazulu_reader/engine/http/engine_http.dart';
import 'package:pazulu_reader/engine/routing/chapter_resolver.dart';
import 'package:pazulu_reader/engine/routing/circuit_breaker.dart';
import 'package:pazulu_reader/engine/routing/smart_router.dart';
import 'package:pazulu_reader/engine/validation/page_validation.dart';

import 'engine_v2_support.dart';

/// Resolver whose image probes return distinct, valid 900x1300 PNGs —
/// no network at all.
ChapterResolver offlineResolver() => ChapterResolver(
      http: EngineHttpClient(
        client: MockClient((_) async => http.Response('no network in tests', 500)),
        checkDns: false,
      ),
      log: EngineLog(),
      probe: (i, url, headers, cancel) async => PageProbe.fromBytes(
          i, url, 200, png(900, 1300, seed: i), complete: true),
    );

SmartSourceRouter router(ConnectorHealthStore health) => SmartSourceRouter(
    resolver: offlineResolver(), breaker: CircuitBreaker(), health: health);

void main() {
  group('Test D — lecteurs alternatifs déterministes', () {
    test('Lecteur 1 erreur, Lecteur 2 six pages valides, Lecteur 3 incomplet => Lecteur 2',
        () async {
      final sources = <String, ContentSource>{
        'one': FakeSource('one', 'error'),
        'two': FakeSource('two', 'valid:6'),
        'three': FakeSource('three', 'partial:4/10'),
      };
      final candidates = [
        chapter('one', '115.1'),
        chapter('two', '115.1'),
        chapter('three', '115.1'),
      ];
      final health = ConnectorHealthStore();
      final outcome = await router(health).route(
        requested: candidates.first,
        candidates: candidates,
        lookup: (id) => sources[id],
      );
      expect(outcome.selectedIndex, 1);
      expect(outcome.pages!.completeness, PageCompleteness.complete);
      expect(outcome.pages!.pages, hasLength(6));
      expect(outcome.steps.first.state, RouteStepState.checking);
      expect(outcome.steps.any((s) => s.index == 0 && s.state == RouteStepState.unavailable),
          isTrue);
      expect(health.of('one').failures, 1);
      expect(health.of('two').successes, 1);
    });

    test('ordre erreur, incomplet, valide => l\'incomplet est refusé', () async {
      final sources = <String, ContentSource>{
        'one': FakeSource('one', 'error'),
        'three': FakeSource('three', 'partial:4/10'),
        'two': FakeSource('two', 'valid:6'),
      };
      final candidates = [
        chapter('one', '115.1'),
        chapter('three', '115.1'),
        chapter('two', '115.1'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, 2);
      expect(outcome.steps.any((s) => s.index == 1 && s.state == RouteStepState.partial),
          isTrue);
    });

    test('le chapitre incomplet seul n\'est jamais annoncé comme réussi', () async {
      final r = await offlineResolver().resolve(
          chapter('three', '115.1'), FakeSource('three', 'partial:4/10'));
      expect(r.completeness, PageCompleteness.partial);
      expect(r.readable, isFalse);
    });

    test('basculement automatique désactivé : un seul lecteur essayé', () async {
      final two = FakeSource('two', 'valid:6');
      final sources = <String, ContentSource>{'one': FakeSource('one', 'error'), 'two': two};
      final candidates = [chapter('one', '12'), chapter('two', '12')];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates,
        lookup: (id) => sources[id], autoFallback: false);
      expect(outcome.selectedIndex, isNull);
      expect(two.calls, 0);
    });
  });

  group('Test B — My Dress-Up Darling 115.1 sur Manga UP!', () {
    test('restriction détectée, 115.2 jamais utilisé, vrai 115.1 ailleurs choisi',
        () async {
      final mangaUp = FakeSource('mangaup', 'restricted');
      final wrong = FakeSource('wrong', 'valid:20');
      final right = FakeSource('mangadex', 'valid:18');
      final sources = <String, ContentSource>{
        'mangaup': mangaUp, 'wrong': wrong, 'mangadex': right,
      };
      final candidates = [
        chapter('mangaup', '115.1'),
        chapter('wrong', '115.2'),
        chapter('mangadex', '115.1', lang: 'fr'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates,
        lookup: (id) => sources[id], edition: 'manga');
      expect(outcome.selectedIndex, 2);
      expect(wrong.calls, 0, reason: '115.2 ne doit même pas être interrogé');
      expect(outcome.steps.any((s) => s.index == 0 && s.state == RouteStepState.restricted),
          isTrue);
      expect(outcome.steps.any((s) =>
          s.index == 1 && s.state == RouteStepState.skippedDifferentChapter), isTrue);
    });

    test('si seul 115.2 existe ailleurs : aucun lecteur, pas de substitution', () async {
      final wrong = FakeSource('wrong', 'valid:20');
      final sources = <String, ContentSource>{
        'mangaup': FakeSource('mangaup', 'restricted'), 'wrong': wrong,
      };
      final candidates = [chapter('mangaup', '115.1'), chapter('wrong', '115.2')];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, isNull);
      expect(outcome.success, isFalse);
      expect(wrong.calls, 0);
      expect(outcome.lastError, isA<ChapterRestrictedException>());
    });

    test('un lien éditeur externe n\'est jamais un lecteur de repli', () async {
      final sources = <String, ContentSource>{'mangaup': FakeSource('mangaup', 'restricted')};
      final candidates = [
        chapter('mangaup', '115.1'),
        chapter('mangadex', '115.1', external: 'https://mangaplus.example/viewer/1'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, isNull);
      expect(outcome.steps.any((s) => s.state == RouteStepState.skippedExternal), isTrue);
    });
  });

  group('Test C — Slime 140 sur K MANGA', () {
    test('vérification d\'âge = restriction ; langue exclue respectée', () async {
      final en = FakeSource('mangadex', 'valid:22');
      final fr = FakeSource('frsource', 'valid:21');
      final sources = <String, ContentSource>{
        'kmanga': FakeSource('kmanga', 'agegate'), 'mangadex': en, 'frsource': fr,
      };
      final candidates = [
        chapter('kmanga', '140'),
        chapter('mangadex', '140', lang: 'en'),
        chapter('frsource', '140', lang: 'fr'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id],
        allowOtherLanguages: false, preferredLanguages: const ['fr'], edition: 'manga');
      expect(outcome.selectedIndex, 2);
      expect(en.calls, 0);
      expect(outcome.steps.any((s) =>
          s.index == 0 && s.state == RouteStepState.restricted &&
          s.message.contains('âge')), isTrue);
    });

    test('même numéro mais volume différent : confirmation, jamais automatique', () async {
      final other = FakeSource('other', 'valid:22');
      final sources = <String, ContentSource>{
        'kmanga': FakeSource('kmanga', 'agegate'), 'other': other,
      };
      final candidates = [
        chapter('kmanga', '140', volume: '31'),
        chapter('other', '140', volume: '20'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, isNull);
      expect(outcome.confirmationCandidates, [1]);
      expect(other.calls, 0);
      final confirmed = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id],
        userConfirmed: {1});
      expect(confirmed.selectedIndex, 1);
    });
  });

  group('Familles de pannes', () {
    test('429 : source mise en pause, repli vers un autre lecteur', () async {
      final sources = <String, ContentSource>{
        'busy': FakeSource('busy', 'ratelimit'), 'ok': FakeSource('ok', 'valid:5'),
      };
      final candidates = [chapter('busy', '3'), chapter('ok', '3')];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, 1);
      expect(outcome.steps.any((s) => s.state == RouteStepState.skippedPaused), isTrue);
    });

    test('chapitre rendu par JavaScript : le routeur demande le WebView2 invisible', () async {
      final sources = <String, ContentSource>{'js': FakeSource('js', 'browser')};
      final candidates = [chapter('js', '5')];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, 0);
      expect(outcome.needsBrowser, isTrue);
    });

    test('source hors ligne (aucun connecteur) : ignorée proprement', () async {
      final candidates = [chapter('gone', '5'), chapter('ok', '5')];
      final sources = <String, ContentSource>{'ok': FakeSource('ok', 'valid:3')};
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, 1);
      expect(outcome.steps.first.state, RouteStepState.skippedNoConnector);
    });

    test('chapitre extra : jamais remplacé par le chapitre 1', () async {
      final one = FakeSource('one', 'valid:9');
      final sources = <String, ContentSource>{
        'a': FakeSource('a', 'error'), 'one': one,
      };
      final candidates = [
        SourceChapter(sourceId: 'a', chapterId: 'x', key: chapter('a', 'Extra 1').key,
            lang: 'en', group: 'a'),
        chapter('one', '1'),
      ];
      final outcome = await router(ConnectorHealthStore()).route(
        requested: candidates.first, candidates: candidates, lookup: (id) => sources[id]);
      expect(outcome.selectedIndex, isNull);
      expect(one.calls, 0);
    });
  });

  group('Circuit breaker et Retry-After', () {
    test('quatre échecs ouvrent le circuit (20 s), expiration puis essai unique', () {
      var now = DateTime(2026, 11, 6, 12);
      final breaker = CircuitBreaker(clock: () => now);
      for (var i = 0; i < 4; i++) {
        expect(breaker.allow('site.example'), isTrue);
        breaker.recordFailure('site.example', reason: 'timeout');
      }
      expect(breaker.allow('site.example'), isFalse);
      now = now.add(const Duration(seconds: 21));
      expect(breaker.allow('site.example'), isTrue, reason: 'half-open trial');
      expect(breaker.allow('site.example'), isFalse, reason: 'one trial at a time');
      breaker.recordSuccess('site.example');
      expect(breaker.allow('site.example'), isTrue);
    });

    test('« Réessayer » relance les sources en pause, sauf un 429', () {
      final breaker = CircuitBreaker();
      for (var i = 0; i < 4; i++) {
        breaker.recordFailure('down.example', reason: 'HTTP 504');
      }
      breaker.openFor('api.example', const Duration(seconds: 120), reason: 'HTTP 429');
      breaker.resetAll();
      expect(breaker.allow('down.example'), isTrue);
      expect(breaker.allow('api.example'), isFalse);
    });

    test('429 : pause exactement égale au Retry-After', () {
      var now = DateTime(2026, 11, 6, 12);
      final breaker = CircuitBreaker(clock: () => now);
      breaker.openFor('api.example', const Duration(seconds: 120), reason: 'HTTP 429');
      expect(breaker.allow('api.example'), isFalse);
      now = now.add(const Duration(seconds: 119));
      expect(breaker.allow('api.example'), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(breaker.allow('api.example'), isTrue);
    });

    test('Retry-After : secondes, date HTTP, plafond d\'une heure', () {
      expect(parseRetryAfter('120'), const Duration(seconds: 120));
      expect(parseRetryAfter('Fri, 06 Nov 2026 12:00:30 GMT',
          now: DateTime.utc(2026, 11, 6, 12)), const Duration(seconds: 30));
      expect(parseRetryAfter('999999'), const Duration(hours: 1));
      expect(parseRetryAfter('bientôt'), isNull);
    });
  });

  group('Classement des sources', () {
    test('à niveau et langue égaux, la source fiable passe devant', () {
      final health = ConnectorHealthStore();
      for (var i = 0; i < 5; i++) {
        health.of('flaky').recordFailure('x');
        health.of('solid').recordSuccess(const Duration(milliseconds: 300));
      }
      final ranked = SourceRanker(health).refine(
        [chapter('flaky', '1'), chapter('solid', '1')],
        tier: (_) => 1,
        langRank: (_) => 0,
      );
      expect(ranked.first.sourceId, 'solid');
    });

    test('la langue préférée reste prioritaire sur la fiabilité', () {
      final health = ConnectorHealthStore();
      health.of('solid').recordSuccess(const Duration(milliseconds: 100));
      final ranked = SourceRanker(health).refine(
        [chapter('solid', '1', lang: 'en'), chapter('new', '1', lang: 'fr')],
        tier: (_) => 1,
        langRank: (c) => c.lang == 'fr' ? 0 : 1,
      );
      expect(ranked.first.sourceId, 'new');
    });
  });
}
