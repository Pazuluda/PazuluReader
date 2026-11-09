import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/sources/mangadex.dart';
import 'package:pazulu_reader/core/suggested_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('200 suggestions are available, but not declared as working connectors', () async {
    final text = await rootBundle.loadString('assets/suggested_sources.json');
    final sites = SuggestedSourceCatalog.parse(text);
    expect(sites.length, 200);
    expect(sites.where((s) => s.language == 'fr').length, 53);
    expect(sites.where((s) => s.language == 'en').length, 147);
    expect(sites.where((s) => s.isReportedAccessible).length, 104);
    expect(sites.where((s) => s.reportedStatus == 'Partiel').length, 10);
    expect(sites.where((s) => s.reportedStatus == 'Non confirmé').length, 86);
  });

  test('a site suggestion cannot inject a local or unsafe URL', () {
    expect(() => SuggestedSourceCatalog.parse('''{
      "format": "pazulu-suggested-sources",
      "sources": [{"rank": 1, "url": "https://127.0.0.1/private",
        "language": "fr", "category": "Manga", "reportedStatus": "Non confirmé"}]
    }'''), throwsFormatException);
  });

  test('MangaDex publisher external URL always outranks a misleading page count', () {
    final chapter = MangaDexSource.parseChapter({
      'id': 'external-test',
      'attributes': {
        'chapter': '112.2', 'title': 'Publisher edition',
        'translatedLanguage': 'en', 'pages': 5,
        'externalUrl': 'https://global.manga-up.com/manga/1/2',
      },
    });
    expect(chapter, isNotNull);
    expect(chapter!.isExternal, isTrue);
    expect(rankVariants([
      chapter,
      SourceChapter(sourceId: 'local', chapterId: 'local-112',
        key: ChapterKey.parse('112.2'), lang: 'fr', group: 'Locally available', pages: 20),
    ], langs: const ['en', 'fr']).first.sourceId, 'local');
  });

  test('external links do not generate fake downloadable chapters', () {
    final links = groupChapters([
      SourceChapter(sourceId: 'listing:x', chapterId: 'external',
        key: ChapterKey.parse('16'), lang: 'en', group: 'Publisher',
        pages: 0, externalUrl: 'https://example.org/chapter/16'),
    ]);
    expect(links.single.variants.single.isExternal, isTrue);
    expect(links.single.variants.where((v) => !v.isExternal), isEmpty);
  });
}
