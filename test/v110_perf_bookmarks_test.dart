import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/bookmarks_import.dart';
import 'package:pazulu_reader/core/site_index.dart';

void main() {
  group('recherche dans l\'index sans bloquer', () {
    final works = [
      for (final t in ['Solo Leveling', 'Solo Max-Level Newbie', 'One Piece', 'The Solo Story', 'Zeta'])
        IndexedWork(SiteTitleIndex.norm(t), t, const []),
    ]..sort((a, b) => a.key.compareTo(b.key));

    test('les titres qui commencent par le texte d\'abord, puis ceux qui le contiennent', () async {
      final hits = await SiteTitleIndex.search(works, 'solo');
      expect(hits.map((w) => w.title).take(2).toSet(), {'Solo Leveling', 'Solo Max-Level Newbie'});
      expect(hits.map((w) => w.title), contains('The Solo Story'));
      expect(hits.map((w) => w.title), isNot(contains('One Piece')));
    });

    test('moins de 2 lettres : rien', () async {
      expect(await SiteTitleIndex.search(works, 's'), isEmpty);
    });

    test('recherche annulée par une nouvelle frappe', () async {
      final many = [
        for (var i = 0; i < 50000; i++) IndexedWork('a$i', 'A$i', const []),
        IndexedWork('zz solo', 'ZZ Solo', const []),
      ];
      final hits = await SiteTitleIndex.search(many, 'solo', cancelled: () => true);
      expect(hits, isEmpty);
    });
  });

  test('index : un fichier par site, relu au démarrage', () async {
    final dir = await Directory.systemTemp.createTemp('pazulu-index');
    try {
      final file = File('${dir.path}/site-index.json');
      final a = SiteTitleIndex(file);
      await a.put('public_a', const [IndexedTitle('One Piece', 'https://a.example/manga/op/')]);
      await a.put('public_b', const [IndexedTitle('ONE PIECE', 'https://b.example/op/')]);
      await a.save();
      expect(Directory('${dir.path}/site-index').listSync().length, greaterThanOrEqualTo(2));
      final b = SiteTitleIndex(file);
      await b.load();
      expect(b.loaded, isTrue);
      expect(b.linksFor(['One Piece']).map((l) => l.sourceId).toSet(), {'public_a', 'public_b'});
      expect(b.works!.single.links.length, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('ancien fichier unique migré en un fichier par site', () async {
    final dir = await Directory.systemTemp.createTemp('pazulu-index');
    try {
      final file = File('${dir.path}/site-index.json');
      await file.writeAsString('{"sites":{"public_a":{"at":"2026-11-01T10:00:00.000",'
          '"titles":[["Solo Leveling","https://a.example/manga/solo-leveling/"]]}},'
          '"failed":{"public_z":"2026-11-01T10:00:00.000"}}');
      final idx = SiteTitleIndex(file);
      await idx.load();
      expect(idx.linksFor(['Solo Leveling']).single.sourceId, 'public_a');
      expect(idx.failedAt.containsKey('public_z'), isTrue);
      expect(file.existsSync(), isFalse);
      expect(File('${dir.path}/site-index/public_a.json').existsSync(), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('import des favoris du navigateur', () {
    const html = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
  <DT><H3>Mangas</H3>
  <DL><p>
    <DT><A HREF="https://www.lecture.example/manga/solo-leveling/chapitre-120/" ADD_DATE="1">Solo Leveling - Chapitre 120 - Lecture</A>
    <DT><A HREF="https://lecture.example/manga/solo-leveling/chapitre-95/">Solo Leveling 95</A>
    <DT><A HREF="https://autre.example/read/omniscient-reader-chapter-201">Omniscient Reader Chapter 201 | Autre</A>
    <DT><A HREF="https://www.youtube.com/watch?v=x">Une vidéo</A>
    <DT><A HREF="https://lecture.example/manga/tower-of-god/">Tower of God</A>
  </DL><p>
</DL>''';

    List<BookmarkReading> run() => findReadings(
          parseBookmarksHtml(html),
          sourceForHost: (h) => h == 'lecture.example' ? 'public_lecture' : null,
          titlesOf: (id) => const [
            IndexedTitle('Solo Leveling', 'https://lecture.example/manga/solo-leveling/'),
            IndexedTitle('Tower of God', 'https://lecture.example/manga/tower-of-god/'),
          ],
          titleKnown: (t) => SiteTitleIndex.norm(t) == 'omniscient reader',
        );

    test('liens lus dans le fichier exporté', () {
      expect(parseBookmarksHtml(html).length, 5);
    });

    test('série et chapitre retrouvés, le plus avancé gardé', () {
      final r = {for (final x in run()) x.title: x};
      expect(r.keys.toSet(), {'Solo Leveling', 'Tower of God', 'Omniscient Reader'});
      expect(r['Solo Leveling']!.chapter, 120);
      expect(r['Solo Leveling']!.seriesUrl, 'https://lecture.example/manga/solo-leveling/');
      expect(r['Tower of God']!.chapter, isNull);
      expect(r['Omniscient Reader']!.chapter, 201);
      expect(r['Omniscient Reader']!.sourceId, isNull);
    });

    test('titre nettoyé', () {
      expect(titleFromBookmark('Solo Leveling - Chapitre 120 - Lecture'), 'Solo Leveling');
      expect(titleFromBookmark('Omniscient Reader Chapter 201 | Autre'), 'Omniscient Reader');
      expect(cleanImportedTitle("Reincarnator's Stream »"), "Reincarnator's Stream");
      expect(cleanImportedTitle('Level Up With Skills »'), 'Level Up With Skills');
      expect(cleanImportedTitle('Solo Leveling'), 'Solo Leveling');
    });
  });
}
