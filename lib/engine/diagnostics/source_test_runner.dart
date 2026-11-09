import 'dart:async';

import '../../core/source.dart';
import '../availability.dart';
import '../routing/chapter_resolver.dart';
import 'connector_health.dart';
import 'engine_log.dart';
import 'source_status.dart';

/// "Tester cette source": search → chapter list → one chapter's pages,
/// validated with real image probes. Sequential, a handful of requests,
/// never a crawl. The verdict follows the audit vocabulary and grants
/// FULL_READER only after a validated chapter.
class SourceTestRunner {
  SourceTestRunner({required this.resolver, required this.log});

  final ChapterResolver resolver;
  final EngineLog log;

  Future<SourceTestReport> run(ContentSource source, {
    required String query,
    required List<String> languages,
    String? workId,
  }) async {
    final total = Stopwatch()..start();
    final steps = <String>[];
    bool? searchOk;
    var searchCount = 0;
    int? searchMs;
    bool? chaptersOk;
    var chapterCount = 0;
    bool? pagesOk;
    String? pageSummary;
    SourceStatus status = SourceStatus.unverified;
    String? error;

    SourceTestReport report() => SourceTestReport(
          sourceId: source.id,
          at: DateTime.now(),
          status: status,
          searchOk: searchOk,
          searchCount: searchCount,
          searchMs: searchMs,
          chaptersOk: chaptersOk,
          chapterCount: chapterCount,
          pagesOk: pagesOk,
          pageSummary: pageSummary,
          totalMs: total.elapsedMilliseconds,
          error: error,
          steps: steps,
        );

    try {
      var target = workId;
      if (target == null) {
        final watch = Stopwatch()..start();
        final results = await source.search(query, limit: 10)
            .timeout(const Duration(seconds: 25));
        searchMs = watch.elapsedMilliseconds;
        searchOk = true;
        searchCount = results.length;
        steps.add('Recherche « $query » : ${results.length} résultat(s) en $searchMs ms.');
        for (final w in results) {
          for (final l in w.links) {
            if (l.sourceId == source.id) {
              target = l.workId;
              break;
            }
          }
          if (target != null) break;
        }
        if (target == null) {
          status = results.isEmpty ? SourceStatus.unverified : SourceStatus.metadataOnly;
          error = results.isEmpty ? 'Aucun résultat pour la requête de test.' : null;
          return report();
        }
      }
      final chapters = await source.listChapters(target, langs: languages)
          .timeout(const Duration(seconds: 40));
      chaptersOk = chapters.isNotEmpty;
      chapterCount = chapters.length;
      steps.add('Chapitres : ${chapters.length}.');
      if (chapters.isEmpty) {
        status = SourceStatus.metadataOnly;
        return report();
      }
      final native = chapters.where((c) => !c.isExternal).toList();
      if (native.isEmpty) {
        status = SourceStatus.externalOnly;
        steps.add('Tous les chapitres renvoient vers un site externe.');
        return report();
      }
      native.sort((a, b) => a.key.compareTo(b.key));
      // Early chapters are the most often freely readable: test one of them.
      final chapter = native.first;
      steps.add('Test du ${chapter.key.longLabel} (${chapter.lang}).');
      try {
        final pages = await resolver.resolve(chapter, source)
            .timeout(const Duration(seconds: 60));
        pagesOk = pages.readable;
        pageSummary = pages.summary;
        steps.add('Pages : ${pages.summary}.');
        status = switch (pages.completeness) {
          PageCompleteness.complete => SourceStatus.fullReader,
          PageCompleteness.unconfirmed || PageCompleteness.partial => SourceStatus.partialReader,
          PageCompleteness.restricted => SourceStatusLabel.fromAccess(pages.access),
          PageCompleteness.invalid => SourceStatus.broken,
        };
        if (!pages.readable) {
          error = pages.issues.where((i) => i.fatal).take(3).join(' ; ');
        }
      } on NeedsBrowserRendering {
        pagesOk = null;
        status = SourceStatus.unverified;
        steps.add('Le chapitre nécessite le rendu WebView2 : ouvrez-le dans le '
            'lecteur pour une validation réelle.');
      }
    } on ChapterRestrictedException catch (e) {
      status = SourceStatusLabel.fromAccess(e.kind);
      error = e.message;
    } on SourceException catch (e) {
      status = e.statusCode == 403 || e.statusCode == 429
          ? SourceStatus.blocked : SourceStatus.broken;
      error = e.message;
    } on TimeoutException {
      status = SourceStatus.broken;
      error = 'Délai dépassé pendant le test.';
    } catch (e) {
      status = SourceStatus.broken;
      error = '$e';
    }
    final result = report();
    log.add(result.status.readable ? EngineLogLevel.info : EngineLogLevel.warning,
        'source_test', sourceId: source.id,
        message: '${result.status.code}${error == null ? '' : ' — $error'}',
        elapsed: total.elapsed);
    return result;
  }
}

/// Default query for a connector test when the manifest has none.
String defaultTestQuery(ContentSource source) => switch (source.id) {
      'mangadex' => 'Solo Leveling',
      'peppercarrot' => 'Pepper',
      'sushiscan_net' => 'Solo Leveling',
      _ => 'a',
    };
