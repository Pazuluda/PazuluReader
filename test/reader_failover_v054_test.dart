import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/reader_failover.dart';

SourceChapter edition(String id, {int total = 0, String? externalUrl}) =>
    SourceChapter(sourceId: id, chapterId: 'chapter-$id',
        key: ChapterKey.parse('12'), lang: 'fr', group: id,
        pages: total, externalUrl: externalUrl);

void main() {
  final good = [
    const PageRef('https://images.example.org/a.jpg'),
    const PageRef('https://images.example.org/b.jpg'),
    const PageRef('https://images.example.org/c.jpg'),
  ];

  test('All three installed versions can be chosen and fail over in order', () {
    final versions = [edition('reader1'), edition('reader2'), edition('reader3')];
    expect(ReaderFailover.next(versions, current: 0, failed: {0},
        canRead: (_) => true), 1);
    expect(ReaderFailover.next(versions, current: 1, failed: {0, 1},
        canRead: (_) => true), 2);
    expect(ReaderFailover.next(versions, current: 2, failed: {0, 1, 2},
        canRead: (_) => true), isNull);
  });

  test('External publisher links and missing connectors are never automatic fallback', () {
    final versions = [edition('down'), edition('external',
        externalUrl: 'https://editor.example/12'), edition('not-installed'), edition('offline')];
    final next = ReaderFailover.next(versions, current: 0, failed: {0},
        canRead: (v) => v.sourceId == 'offline');
    expect(next, 3);
  });

  test('An advertised 13-page chapter cannot pass with 8 image URLs', () {
    final partial = List.generate(8, (i) => PageRef('https://cdn.example.org/$i.webp'));
    expect(() => ReaderFailover.validatePages(edition('site', total: 13), partial),
        throwsException);
    expect(() => ReaderFailover.validatePages(edition('site', total: 3), good),
        returnsNormally);
  });

  test('No empty, repeated, HTTP or local-network image URLs', () {
    final chapter = edition('source');
    expect(() => ReaderFailover.validatePages(chapter, []), throwsException);
    expect(() => ReaderFailover.validatePages(chapter, [good.first, good.first]),
        throwsException);
    expect(() => ReaderFailover.validatePages(chapter,
        [const PageRef('http://cdn.example.org/page.jpg')]), throwsException);
    expect(() => ReaderFailover.validatePages(chapter,
        [const PageRef('https://127.0.0.1/secret.jpg')]), throwsException);
    expect(() => ReaderFailover.validatePages(chapter,
        [const PageRef('https://localhost/secret.jpg')]), throwsException);
    expect(() => ReaderFailover.validatePages(chapter,
        [const PageRef('hors-ligne:0')], offline: true), returnsNormally);
  });
}
