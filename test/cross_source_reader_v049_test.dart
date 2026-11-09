import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_identity.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/downloads.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/zip.dart';

SourceChapter variant(String number, String lang, String name) => SourceChapter(
  sourceId: name, chapterId: '$name-$lang-$number',
  key: ChapterKey.parse(number), lang: lang, group: name, pages: 2,
);

void main() {
  test('A chapter shares one key across sites, FR/EN and CBZ', () {
    final grouped = groupChapters([
      variant('15', 'en', 'mangadex'),
      variant('15.0', 'fr', 'archive'),
      variant('15', 'en', 'other'),
      variant('16', 'en', 'other'),
    ]);
    expect(grouped.length, 2);
    expect(grouped.first.variants.length, 3);
    expect(grouped.first.languages, {'en', 'fr'});
  });

  test('resume keeps last position when source changed', () {
    final groups = groupChapters([
      variant('15', 'fr', 'archive'), variant('16', 'en', 'other'),
    ]);
    expect(resumePosition(groups, ReadingProgress(lastKey: '15', lastPage: 4)), (0, 4));
    expect(resumePosition(groups,
      ReadingProgress(lastKey: '15', lastPage: 7, readKeys: {'15'})), (1, 0));
  });

  test('resume finds next available chapter when old source disappeared', () {
    final groups = groupChapters([
      variant('20', 'en', 'other'), variant('22', 'en', 'other'),
    ]);
    expect(resumePosition(groups, ReadingProgress(lastKey: '19', lastPage: 5)), (0, 0));
    expect(resumePosition(groups, ReadingProgress(lastKey: '21', lastPage: 8)), (1, 0));
  });

  test('number detection avoids year and series identifiers', () {
    expect(ChapterIdentity.detect(title: 'Chapter 16: 015 Dungeon Boss')?.id, '16');
    expect(ChapterIdentity.detect(title: 'Solo Leveling',
      url: 'https://example.org/comic/solo-leveling/chapter-115.5')?.id, '115.5');
    expect(ChapterIdentity.detect(title: 'Chapitre 16.cbz')?.id, '16');
    expect(ChapterIdentity.detect(title: '16.cbz')?.id, '16');
    expect(ChapterIdentity.detect(title: 'The 2026 Hero') , isNull);
  });

  test('imported zip becomes a readable chapter of the SAME work', () async {
    final temp = await Directory.systemTemp.createTemp('pazulu-049-');
    addTearDown(() async { if (await temp.exists()) await temp.delete(recursive: true); });
    final image = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    final source = File('${temp.path}/Chapitre 15.cbz');
    await source.writeAsBytes(writeZip([
      ZipEntry('pages/1.jpg', image),
      ZipEntry('pages/2.jpg', image),
      ZipEntry('README.txt', Uint8List.fromList([72, 105])),
    ]));
    final store = DownloadStore(temp);
    final work = WorkInfo(id: 'mangadex:123', title: 'Test Manhwa');
    final count = await store.importIntoWork(
      work: work, paths: [source.path], language: 'fr',
    );
    expect(count, 1);
    final records = store.forWork(work.id);
    expect(records.length, 1);
    expect(records.single.keyId, '15');
    expect(records.single.lang, 'fr');
    expect(records.single.pages, 2);
    expect((await store.readPages(records.single)).length, 2);
    expect(await source.exists(), isTrue);

    final reopened = DownloadStore(temp);
    await reopened.load();
    expect(reopened.forWork(work.id).length, 1);
    final groups = groupChapters([
      variant('15', 'en', 'mangadex'),
      ...reopened.forWork(work.id).map((r) => r.toChapter()),
    ]);
    expect(groups.single.languages, {'en', 'fr'});
  });

  test('does not silently guess chapter from random digits in file name', () async {
    final temp = await Directory.systemTemp.createTemp('pazulu-049-');
    addTearDown(() async { if (await temp.exists()) await temp.delete(recursive: true); });
    final path = '${temp.path}/Hero 2026.cbz';
    await File(path).writeAsBytes(writeZip([
      ZipEntry('001.jpg', Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]))
    ]));
    final store = DownloadStore(temp);
    await expectLater(store.importIntoWork(
      work: const WorkInfo(id: 'test', title: 'Test'),
      paths: [path], language: 'fr'), throwsFormatException);
  });
}
