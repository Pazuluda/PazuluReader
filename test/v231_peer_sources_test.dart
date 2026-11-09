import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/release_detector.dart';
import 'package:pazulu_reader/core/schedule/site_latest.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';
import 'package:pazulu_reader/ui/format.dart';

SourceChapter ch(String key, String source, {DateTime? published, String lang = 'en'}) =>
    SourceChapter(sourceId: source, chapterId: '$source-$key', key: ChapterKey.parse(key),
        lang: lang, group: source, pages: 3, publishedAt: published);

void main() {
  final now = DateTime(2026, 11, 7, 12);

  test('aucune source de référence : MangaDex est vérifiée comme les autres', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'));
    e.latestKnown['en'] = 50;
    // MangaDex itself cannot inject an absurd number either.
    final fresh = ReleaseDetector.observe(e, 'mangadex', [ch('3861', 'mangadex'), ch('51', 'mangadex')],
        langs: ['en'], now: now);
    expect(fresh.map((c) => c.key.id), ['51']);
    expect(e.latestKnown['en'], 51);
  });

  test('liste complète d\'un site (1…330) : dernier chapitre connu mis à jour d\'un coup', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'));
    e.latestKnown['en'] = 50;
    ReleaseDetector.observe(e, 'public_x', [for (var i = 1; i <= 330; i++) ch('$i', 'public_x')],
        langs: ['en'], now: now);
    expect(e.latestKnown['en'], 330);
  });

  test('référence des notifications calculée sur toutes les sources', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'));
    e.observedChapters['public_a|en'] = [for (var i = 1; i <= 330; i++) '$i'];
    e.observedChapters['mangadex|en'] = [for (var i = 1; i <= 50; i++) '$i'];
    e.observedChapters['public_b|en'] = ['1', '2', '3', '3861'];
    expect(UpdateHygiene.trustedReference(e), 330);
  });

  test('date de sortie lue sur la liste de chapitres d\'un site', () {
    const site = CatalogSite('directory_042', 'ManhuaUS', 'https://manhuaus.com/', ['en'],
        SiteIntegration.website);
    final source = PublicCatalogSource(site, fetchHtml: (_) async => '');
    final list = source.parseChapterList('''
<ul><li class="wp-manga-chapter"><a href="https://manhuaus.com/manga/x/chapter-12/">Chapter 12</a>
<span class="chapter-release-date"><i>May 6, 2026</i></span></li></ul>''',
        Uri.parse('https://manhuaus.com/manga/x/'), lang: 'en');
    expect(list.single.publishedAt, DateTime(2026, 5, 6));
  });

  test('« sorti il y a » lisible, jamais une date seule', () {
    expect(releaseLine(now.subtract(const Duration(hours: 3)), now: now), 'Sorti il y a 3 h');
    expect(releaseLine(DateTime(2026, 5, 6), now: now), 'Sorti le 6 mai 2026 · il y a 6 mois');
    expect(releaseAge(DateTime(2023, 6, 1), now: now), 'il y a 3 ans');
  });

  test('date de première sortie d\'un chapitre (toutes sources)', () {
    final g = ChapterGroup(ChapterKey.parse('10'), [
      ch('10', 'a', published: DateTime(2026, 3, 2)),
      ch('10', 'b', published: DateTime(2026, 3, 1), lang: 'fr'),
    ]);
    expect(g.firstDate, DateTime(2026, 3, 1));
  });

  test('heure dans le titre du lien Madara', () {
    final r = SiteLatestParser.parse('''
<div class="page-item-detail"><h3 class="h5"><a href="/manga/a/">Alpha Series</a></h3>
<div class="chapter-item"><span class="chapter"><a href="/manga/a/chapter-3/">Chapter 3</a></span>
<span class="post-on"><a title="5 hours ago">new</a></span></div></div>''',
        Uri.parse('https://s.example/'), now: now);
    expect(r.single.at, now.subtract(const Duration(hours: 5)));
  });
}
