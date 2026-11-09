// Shared helpers for the Pazulu Source Engine 2.0 tests (not a test file).
import 'dart:io';
import 'dart:typed_data';

import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source.dart';
import 'package:pazulu_reader/engine/availability.dart';
import 'package:pazulu_reader/engine/source_contract.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Uint8List _withPadding(List<int> head, int seed) => Uint8List.fromList([
      ...head,
      // Distinct payload per seed so content hashes differ.
      for (var i = 0; i < 64; i++) (seed * 31 + i * 7) & 0xFF,
    ]);

Uint8List png(int w, int h, {int seed = 0}) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  b.setUint8(12, 0x49); // I
  b.setUint8(13, 0x48); // H
  b.setUint8(14, 0x44); // D
  b.setUint8(15, 0x52); // R
  b.setUint32(16, w);
  b.setUint32(20, h);
  b.setUint8(24, 8);
  b.setUint8(25, 2);
  return _withPadding(b.buffer.asUint8List(), seed);
}

Uint8List jpeg(int w, int h, {int seed = 0}) => _withPadding([
      0xFF, 0xD8,
      0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
      0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      0xFF, 0xC0, 0x00, 0x11, 0x08, (h >> 8) & 0xFF, h & 0xFF,
      (w >> 8) & 0xFF, w & 0xFF, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01,
      0x03, 0x11, 0x01,
    ], seed);

Uint8List gif(int w, int h) => _withPadding([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
      w & 0xFF, (w >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF, 0, 0, 0,
    ], 1);

Uint8List webpVp8x(int w, int h) {
  final ww = w - 1;
  final hh = h - 1;
  return _withPadding([
    0x52, 0x49, 0x46, 0x46, 0x30, 0x00, 0x00, 0x00, // RIFF size
    0x57, 0x45, 0x42, 0x50, // WEBP
    0x56, 0x50, 0x38, 0x58, // VP8X
    0x0A, 0x00, 0x00, 0x00, // chunk size
    0x00, 0x00, 0x00, 0x00, // flags + reserved
    ww & 0xFF, (ww >> 8) & 0xFF, (ww >> 16) & 0xFF,
    hh & 0xFF, (hh >> 8) & 0xFF, (hh >> 16) & 0xFF,
  ], 2);
}

SourceChapter chapter(String source, String number, {String lang = 'en',
    int pages = 0, String? volume, String? external}) => SourceChapter(
      sourceId: source,
      chapterId: 'https://$source.example/ch-$number',
      key: ChapterKey.parse(number),
      lang: lang,
      group: source,
      title: 'Chapter $number',
      pages: pages,
      volume: volume,
      externalUrl: external,
    );

/// Deterministic in-memory connector for router tests.
class FakeSource implements ContentSource, PageResolvingSource {
  FakeSource(this.id, this.behaviour);

  @override
  final String id;

  /// 'error' | 'valid:N' | 'partial:N/M' | 'restricted' | 'ratelimit' | 'browser'
  final String behaviour;
  int calls = 0;

  @override
  String get name => 'Source $id';
  @override
  List<String> get languages => const ['en', 'fr'];
  @override
  Map<String, String> get imageHeaders => const {};
  @override
  String get credit => '';

  @override
  Future<PageFetch> fetchPages(SourceChapter chapter) async {
    calls++;
    if (behaviour == 'error') {
      throw const SourceException('Connexion impossible (fake).');
    }
    if (behaviour == 'restricted') {
      throw const ChapterRestrictedException('Ce chapitre n\'est plus gratuit.',
          kind: AccessKind.subscriptionRequired);
    }
    if (behaviour == 'agegate') {
      throw const ChapterRestrictedException('Vérification d\'âge.',
          kind: AccessKind.ageVerification);
    }
    if (behaviour == 'ratelimit') {
      throw const ChapterRestrictedException('HTTP 429',
          kind: AccessKind.rateLimited, statusCode: 429,
          retryAfter: Duration(seconds: 120));
    }
    if (behaviour == 'browser') {
      return PageFetch(pages: const [], needsBrowser: true, transport: 'browser');
    }
    final valid = RegExp(r'^valid:(\d+)$').firstMatch(behaviour);
    if (valid != null) {
      final n = int.parse(valid.group(1)!);
      return PageFetch(
        pages: [for (var i = 1; i <= n; i++) PageRef('https://img.$id.example/${chapter.key.id}/$i.png')],
        announcedTotal: n,
        transport: 'api',
      );
    }
    final partial = RegExp(r'^partial:(\d+)/(\d+)$').firstMatch(behaviour);
    if (partial != null) {
      final got = int.parse(partial.group(1)!);
      return PageFetch(
        pages: [for (var i = 1; i <= got; i++) PageRef('https://img.$id.example/${chapter.key.id}/$i.png')],
        announcedTotal: int.parse(partial.group(2)!),
        transport: 'html',
      );
    }
    throw StateError('Comportement inconnu $behaviour');
  }

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async =>
      (await fetchPages(chapter)).pages;
  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async => const [];
  @override
  Future<WorkInfo> getWork(String workId) async => throw UnimplementedError();
  @override
  Future<List<SourceChapter>> listChapters(String workId, {
    required List<String> langs,
  }) async => const [];
  @override
  Future<List<SourceChapter>> latestChapters(String workId, {
    required List<String> langs, int limit = 30,
  }) async => const [];
}
