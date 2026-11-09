import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:pazulu_reader/engine/http/html_extract.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';
import 'package:pazulu_reader/core/work_status.dart';

void main() {
  final now = DateTime(2026, 11, 8);

  test('libellés FR / EN reconnus', () {
    expect(WorkStatusEngine.parse('OnGoing'), SeriesStatus.ongoing);
    expect(WorkStatusEngine.parse('RELEASING'), SeriesStatus.ongoing);
    expect(WorkStatusEngine.parse('En pause'), SeriesStatus.hiatus);
    expect(WorkStatusEngine.parse('Hiatus'), SeriesStatus.hiatus);
    expect(WorkStatusEngine.parse('Dropped'), SeriesStatus.cancelled);
    expect(WorkStatusEngine.parse('Axed'), SeriesStatus.cancelled);
    expect(WorkStatusEngine.parse('Annulé'), SeriesStatus.cancelled);
    expect(WorkStatusEngine.parse('Completed'), SeriesStatus.completed);
    expect(WorkStatusEngine.parse('Terminé'), SeriesStatus.completed);
  });

  test('AniList « terminé » l\'emporte sur un site resté « OnGoing »', () {
    final d = WorkStatusEngine.decide(const [
      StatusVote('AniList', SeriesStatus.completed, 3),
      StatusVote('site a', SeriesStatus.ongoing, 1),
      StatusVote('site b', SeriesStatus.ongoing, 1),
    ], now: now);
    expect(d.status, SeriesStatus.completed);
  });

  test('« en cours » sans chapitre depuis 5 mois : en pause', () {
    final d = WorkStatusEngine.decide(const [StatusVote('site', SeriesStatus.ongoing, 1)],
        lastRelease: DateTime(2026, 6, 1), now: now);
    expect(d.status, SeriesStatus.hiatus);
  });

  test('aucun chapitre depuis 2 ans : annulée', () {
    final d = WorkStatusEngine.decide(const [], lastRelease: DateTime(2024, 9, 1), now: now);
    expect(d.status, SeriesStatus.cancelled);
    expect(d.status.active, isFalse);
  });

  test('chapitre récent : en cours, dans le planning', () {
    final d = WorkStatusEngine.decide(const [], lastRelease: DateTime(2026, 11, 1), now: now);
    expect(d.status, SeriesStatus.ongoing);
    expect(d.status.active, isTrue);
  });

  test('statut lu sur une fiche Madara et MangaThemesia', () {
    expect(PublicCatalogSource.statusOnPage(
        '<script>if(x.status==200){}</script><div class="post-status"><div class="summary-heading">'
        '<h5>Status</h5></div><div class="summary-content">OnGoing</div></div>'), 'OnGoing');
    expect(PublicCatalogSource.statusOnPage(
        '<div class="imptdt">Statut <i>Terminé</i></div>'), 'Terminé');
  });

  test('libellé de chapitre : pas de chiffres collés (272 + 28 ≠ 27228)', () {
    final a = html.parseFragment('<a><span>Chapter 272</span><span>28 Oct</span></a>')
        .querySelector('a')!;
    expect(HtmlExtract.spacedText(a), 'Chapter 272 28 Oct');
  });

  test('AniList « en pause » mais chapitre sorti il y a 5 jours : en cours (reprise)', () {
    final d = WorkStatusEngine.decide(const [StatusVote('AniList', SeriesStatus.hiatus, 3)],
        lastRelease: DateTime(2026, 11, 3), now: now);
    expect(d.status, SeriesStatus.ongoing);
    expect(d.reason, contains('reprise'));
  });

  test('dernier chapitre sans date : une vieille date ne met pas la série en pause', () {
    final d = WorkStatusEngine.decide(const [StatusVote('AniList', SeriesStatus.ongoing, 3)],
        lastRelease: DateTime(2026, 3, 1), now: now, lastReleaseIsNewest: false);
    expect(d.status, SeriesStatus.ongoing);
  });
}
