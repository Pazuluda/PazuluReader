import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source_routing.dart';

SourceChapter chapter(String id, String source, {String? url, String lang = 'en'}) =>
  SourceChapter(sourceId: source, chapterId: id, key: ChapterKey.parse('15'),
    lang: lang, group: source, externalUrl: url);

void main() {
  test('a catalogue link is not treated as a readable chapter', () {
    final external = chapter('c1', 'mangaplus', url: 'https://example.org/chapter/15');
    expect(SourceRouting.access(external, isCached: (_) => false,
      hasConnector: (_) => false, recentlyFailed: (_) => false), SourceAccess.external);
    expect(SourceRouting.canOpenInPazulu(external, isCached: (_) => false,
      hasConnector: (_) => false, recentlyFailed: (_) => false), false);
  });
  test('offline is preferred, including when the original site vanished', () {
    final linked = chapter('c1', 'site', url: 'https://example.org/chapter/15');
    final offline = chapter('c2', 'oldsite');
    final native = chapter('c3', 'mangadex');
    final ranked = SourceRouting.rank([linked, native, offline],
      preferredLanguages: ['fr', 'en'],
      isCached: (id) => id == 'c2',
      hasConnector: (id) => id == 'mangadex',
      recentlyFailed: (_) => false);
    expect(ranked.map((c) => c.chapterId), ['c2','c3','c1']);
    expect(SourceRouting.canOpenInPazulu(offline, isCached: (id) => id == 'c2',
      hasConnector: (_) => false, recentlyFailed: (_) => false), true);
  });
  test('a recent 404 is deprioritized, not permanently deleted', () {
    final failed = chapter('c1', 'md');
    final backup = chapter('c2', 'pc');
    final ranked = SourceRouting.rank([failed,backup],
      preferredLanguages: ['en'], isCached: (_) => false,
      hasConnector: (_) => true,
      recentlyFailed: (id) => id == 'c1');
    expect(ranked.first.chapterId, 'c2');
    expect(SourceRouting.canOpenInPazulu(failed,
      isCached: (_) => false, hasConnector: (_) => true,
      recentlyFailed: (_) => true), false);
  });
  test('multiple native sources are sorted by preferred language', () {
    final en = chapter('c1','a',lang:'en');
    final fr = chapter('c2','b',lang:'fr');
    final ranked = SourceRouting.rank([en, fr], preferredLanguages: ['fr','en'],
      isCached: (_) => false, hasConnector: (_) => true,
      recentlyFailed: (_) => false);
    expect(ranked.first.lang, 'fr');
  });
}
