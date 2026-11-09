import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/downloads.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source.dart';

class _CatalogSource implements ContentSource {
  int pagesRequested = 0;

  final chapter = SourceChapter(
    sourceId: 'demo',
    chapterId: 'demo-chapter-16',
    key: ChapterKey.parse('16'),
    lang: 'fr',
    group: 'Demonstration',
    pages: 1,
  );

  final work = const WorkInfo(
    id: 'demo:work',
    title: 'Livre de demonstration',
    description: 'Resume sans telechargement des pages.',
    languages: ['fr', 'en'],
    links: [SourceLink(sourceId: 'demo', workId: 'work')],
  );

  @override String get id => 'demo';
  @override String get name => 'Source de test';
  @override String get credit => 'Images de test uniquement';
  @override List<String> get languages => const ['fr', 'en'];
  @override Map<String, String> get imageHeaders => const {};
  @override Future<List<WorkInfo>> search(String q, {int limit = 30}) async => [work];
  @override Future<WorkInfo> getWork(String id) async => work;
  @override Future<List<SourceChapter>> listChapters(String id, {required List<String> langs}) async =>
      langs.contains(chapter.lang) ? [chapter] : [];
  @override Future<List<SourceChapter>> latestChapters(String id, {
    required List<String> langs, int limit = 30,
  }) => listChapters(id, langs: langs);
  @override Future<List<PageRef>> getPages(SourceChapter chapter) async {
    pagesRequested++;
    return [const PageRef('https://images.example.org/0001.png')];
  }
}

void main() {
  // A tiny valid PNG fixture; it must be saved as an image rather than HTML.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl51z8AAAAASUVORK5CYII=',
  );

  test('discovery and summary do not fetch chapter images', () async {
    final source = _CatalogSource();
    final found = await source.search('Livre');
    final summary = await source.getWork('work');
    final chapters = await source.listChapters('work', langs: ['fr']);
    expect(found.single.id, summary.id);
    expect(summary.description, isNotEmpty);
    expect(chapters.single.key.id, '16');
    expect(source.pagesRequested, 0);
  });

  test('first reading downloads CBZ and local pages can be reused', () async {
    final dir = await Directory.systemTemp.createTemp('pazulu_read_on_demand_');
    try {
      final source = _CatalogSource();
      final store = DownloadStore(dir);
      final client = MockClient((request) async {
        expect(request.url.host, 'images.example.org');
        return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
      });
      expect(source.pagesRequested, 0);
      await store.download(
        work: source.work,
        chapter: source.chapter,
        source: source,
        onProgress: (_) {},
        client: client,
      );
      expect(source.pagesRequested, 1);
      final saved = store.byChapter(source.chapter.chapterId);
      expect(saved, isNotNull);
      expect(await File(saved!.path).exists(), isTrue);
      final images = await store.readPages(saved);
      expect(images.single, png);
      await store.load();
      expect(store.byChapter(source.chapter.chapterId), isNotNull);
      expect(source.pagesRequested, 1);
      client.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('HTTP 200 with a HTML challenge is not mistaken for a chapter image', () async {
    final dir = await Directory.systemTemp.createTemp('pazulu_bad_html_');
    try {
      final source = _CatalogSource();
      final store = DownloadStore(dir);
      final client = MockClient((request) async => http.Response(
        '<html>captcha</html>', 200,
        headers: {'content-type': 'text/html'},
      ));
      await expectLater(
        store.download(
          work: source.work,
          chapter: source.chapter,
          source: source,
          onProgress: (_) {},
          client: client,
        ),
        throwsA(isA<SourceException>()),
      );
      expect(store.byChapter(source.chapter.chapterId), isNull);
      client.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('automatic cache can be disabled and old settings enable it by default', () {
    final previous = Settings.fromJson(const <String, dynamic>{});
    expect(previous.cacheOnRead, isTrue);
    previous.cacheOnRead = false;
    final restored = Settings.fromJson(previous.toJson());
    expect(restored.cacheOnRead, isFalse);
  });
}
