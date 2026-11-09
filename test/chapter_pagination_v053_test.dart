import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/browser_page_turn.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapter_pagination.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/sources/sushiscan.dart';
import 'package:pazulu_reader/core/visible_pages.dart';

void main() {
  const chapterUrl = 'https://sushiscan.net/solo-leveling-chap-198/';
  final options = [for (var n = 1; n <= 14; n++)
    '<option value="$n"${n == 1 ? ' selected' : ''}>$n/14</option>'].join();
  final html = '<html><body><select id="pageSelection" name="page">'
      '$options</select><div id="readerarea"><img '
      'src="https://cdn.example.org/solo/01.webp"></div></body></html>';

  test('HTML page par page: 14 options mais une seule image visible', () {
    final document = parser.parse(html);
    expect(ChapterPagination.totalFromHtml(document), 14,
        reason: 'Les 14 options doivent primer sur leur texte concaténé (1/142/14).');
    expect(SushiScanSource.parsePages(html, chapterUrl).length, 1);
  });

  test('Le connecteur ne rend pas un faux chapitre complet 1/1', () async {
    final source = SushiScanSource(client: MockClient((request) async =>
      http.Response(html, 200)));
    final chapter = SourceChapter(sourceId: 'sushiscan_net',
        chapterId: chapterUrl, key: ChapterKey.parse('198'),
        lang: 'fr', group: 'SushiScan', title: 'Chapitre 198');
    await expectLater(source.getPages(chapter),
        throwsA(isA<Exception>().having((e) => e.toString(), 'diagnostic',
            contains('1/14'))));
  });

  test('Snapshot WebView: l image 1 ne vaut pas tout le chapitre', () {
    final snapshot = ChapterPagination.fromBrowser(jsonEncode({
      'url': chapterUrl,
      'images': ['https://cdn.example.org/solo/01.webp'],
      'pagination': {'total': 14, 'current': 1, 'selectIndex': 2},
    }), chapterUrl: chapterUrl);
    expect(snapshot.pages, hasLength(1));
    expect(snapshot.isIncomplete, isTrue);
    expect(snapshot.selectIndex, 2);
    expect(snapshot.current, 1);
  });

  test('Le pilote ne devine aucune URL et exige une confirmation de changement', () {
    final script = browserTurnToPageScript(14, 2);
    expect(script, contains('selectedIndex = index'));
    expect(script, contains("new Event('change'"));
    expect(script, isNot(contains('fetch(')));
    expect(browserTurnAccepted(jsonEncode({'accepted': true})), isTrue);
    expect(browserTurnAccepted(jsonEncode({'accepted': false})), isFalse);
    expect(() => browserTurnToPageScript(301, 0), throwsArgumentError);
    expect(visiblePagesScript, contains('pagination'));
  });

  test('Chapitre vertical de deux images: aucune pagination inventee', () {
    final snapshot = ChapterPagination.fromBrowser({
      'url': chapterUrl,
      'images': [
        'https://cdn.example.org/solo/01.webp',
        'https://cdn.example.org/solo/02.webp',
      ],
      'pagination': {'total': null, 'current': 1, 'selectIndex': null},
    }, chapterUrl: chapterUrl);
    expect(snapshot.isPaged, isFalse);
    expect(snapshot.pages, hasLength(2));
  });

  test('Pas de navigation vers une autre fiche ou un autre domaine', () {
    expect(() => ChapterPagination.fromBrowser({
      'url': 'https://sushiscan.net/solo-leveling-chap-199/',
      'images': ['https://cdn.example.org/01.webp'],
    }, chapterUrl: chapterUrl), throwsFormatException);
    expect(() => ChapterPagination.fromBrowser({
      'url': 'https://other.example/solo-leveling-chap-198/',
      'images': ['https://cdn.example.org/01.webp'],
    }, chapterUrl: chapterUrl), throwsFormatException);
  });
}
