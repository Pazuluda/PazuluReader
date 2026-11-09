import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/library_store.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/sources/mangadex.dart';
import 'package:pazulu_reader/core/zip.dart';
import 'dart:typed_data';

SourceChapter ch(
  String number,
  String lang, {
  String group = 'G',
  String id = '',
  int pages = 20,
  String? external,
  DateTime? date,
}) =>
    SourceChapter(
      sourceId: 'mangadex',
      chapterId: id.isEmpty ? '$number-$lang-$group' : id,
      key: ChapterKey.parse(number),
      lang: lang,
      group: group,
      pages: pages,
      externalUrl: external,
      publishedAt: date,
    );

void main() {
  group('ChapterKey', () {
    test('normalise les numéros', () {
      expect(ChapterKey.parse('12').id, '12');
      expect(ChapterKey.parse('12.0').id, '12');
      expect(ChapterKey.parse('12,5').id, '12.5');
      expect(ChapterKey.parse('Ch. 7').id, '7');
      expect(ChapterKey.parse(null).id, 'oneshot');
      expect(ChapterKey.parse('Extra').isSpecial, isTrue);
    });

    test('trie dans l\'ordre numérique', () {
      final keys = ['10', '2', '2.5', '1', 'Extra']
          .map(ChapterKey.parse)
          .toList()
        ..sort();
      expect(keys.map((k) => k.id), ['extra', '1', '2', '2.5', '10']);
    });

    test('égalité par identifiant', () {
      expect(ChapterKey.parse('3'), ChapterKey.parse('3.0'));
    });
  });

  group('Regroupement et lecteurs', () {
    test('regroupe les versions d\'un même chapitre', () {
      final groups = groupChapters([
        ch('1', 'en'),
        ch('1', 'fr'),
        ch('2', 'en'),
        ch('1', 'en', group: 'Autre'),
      ]);
      expect(groups.length, 2);
      expect(groups.first.variants.length, 3);
      expect(groups.first.languages, {'en', 'fr'});
    });

    test('élimine les doublons stricts', () {
      final groups = groupChapters([ch('1', 'en', id: 'x'), ch('1', 'en', id: 'x')]);
      expect(groups.single.variants.length, 1);
    });

    test('Lecteur 1 = langue préférée, lien externe en dernier', () {
      final ranked = rankVariants(
        [
          ch('1', 'en', group: 'Officiel', pages: 0, external: 'https://exemple.org'),
          ch('1', 'fr', group: 'FR'),
          ch('1', 'en', group: 'EN'),
        ],
        langs: ['fr', 'en'],
      );
      expect(ranked.map((c) => c.group), ['FR', 'EN', 'Officiel']);
    });

    test('le lecteur par défaut passe devant la langue', () {
      final ranked = rankVariants(
        [ch('1', 'fr', group: 'FR'), ch('1', 'en', group: 'Préféré')],
        langs: ['fr', 'en'],
        preferredLang: 'en',
        preferredGroup: 'Préféré',
      );
      expect(ranked.first.group, 'Préféré');
    });

    test('détecte les chapitres manquants dans une langue', () {
      final groups = groupChapters([
        for (var i = 1; i <= 10; i++) ch('$i', 'en'),
        for (var i = 1; i <= 6; i++) ch('$i', 'fr'),
        ch('9', 'fr'),
      ]);
      final missing = missingInLanguage(groups, 'fr');
      expect(missing.map((r) => r.toString()), ['7–8', '10']);
      expect(missingInLanguage(groups, 'en'), isEmpty);
    });

    test('reprise : page enregistrée ou chapitre suivant si terminé', () {
      final groups = groupChapters([ch('1', 'en'), ch('2', 'en'), ch('3', 'en')]);
      expect(resumePosition(groups, ReadingProgress()), (0, 0));
      expect(resumePosition(groups, ReadingProgress(lastKey: '2', lastPage: 7)), (1, 7));
      expect(
        resumePosition(groups, ReadingProgress(lastKey: '2', lastPage: 19, readKeys: {'2'})),
        (2, 0),
      );
    });
  });

  group('MangaDex', () {
    test('analyse une fiche', () {
      final w = MangaDexSource.parseManga({
        'id': 'abc',
        'attributes': {
          'title': {'ko-ro': 'Na Honjaman'},
          'altTitles': [
            {'en': 'Solo Test'},
            {'fr': 'Test en solo'},
          ],
          'description': {'en': 'Desc EN', 'fr': 'Desc FR'},
          'status': 'ongoing',
          'year': 2018,
          'originalLanguage': 'ko',
          'availableTranslatedLanguage': ['en', 'fr'],
          'tags': [
            {
              'attributes': {
                'name': {'en': 'Long Strip'},
              },
            },
            {
              'attributes': {
                'name': {'en': 'Action'},
              },
            },
          ],
        },
        'relationships': [
          {
            'type': 'cover_art',
            'attributes': {'fileName': 'cover.png'},
          },
          {
            'type': 'author',
            'attributes': {'name': 'Auteur'},
          },
        ],
      });
      expect(w.id, 'mangadex:abc');
      expect(w.title, 'Solo Test');
      expect(w.description, 'Desc FR');
      expect(w.type, ContentType.manhwa);
      expect(w.longStrip, isTrue);
      expect(w.coverUrl, 'https://uploads.mangadex.org/covers/abc/cover.png.512.jpg');
      expect(w.links.single.workId, 'abc');
      expect(w.publicationStatus, 'En cours');
    });

    test('analyse un chapitre et ignore les chapitres vides', () {
      final c = MangaDexSource.parseChapter({
        'id': 'c1',
        'attributes': {
          'chapter': '12.5',
          'translatedLanguage': 'fr',
          'pages': 30,
          'readableAt': '2026-10-01T10:00:00+00:00',
        },
        'relationships': [
          {
            'type': 'scanlation_group',
            'attributes': {'name': 'Team FR'},
          },
        ],
      });
      expect(c, isNotNull);
      expect(c!.key.id, '12.5');
      expect(c.group, 'Team FR');
      expect(c.lang, 'fr');

      final empty = MangaDexSource.parseChapter({
        'id': 'c2',
        'attributes': {'chapter': '1', 'translatedLanguage': 'en', 'pages': 0},
      });
      expect(empty, isNull);
    });

    test('construit les adresses des pages', () {
      final pages = MangaDexSource.parseAtHome({
        'baseUrl': 'https://srv.example',
        'chapter': {
          'hash': 'h',
          'data': ['1.png', '2.png'],
          'dataSaver': ['1.jpg', '2.jpg'],
        },
      });
      expect(pages.length, 2);
      expect(pages.first.url, 'https://srv.example/data/h/1.png');
      expect(pages.first.fallbackUrl, 'https://srv.example/data-saver/h/1.jpg');
    });
  });

  group('Stockage et sauvegarde', () {
    LibraryData sample() {
      final data = LibraryData();
      final e = LibraryEntry(
        work: const WorkInfo(
          id: 'mangadex:abc',
          title: 'Titre',
          links: [SourceLink(sourceId: 'mangadex', workId: 'abc')],
        ),
        status: TrackStatus.reading,
      );
      e.progress.lastKey = '5';
      e.progress.readKeys.addAll({'1', '2', '3', '4'});
      data.entries[e.work.id] = e;
      return data;
    }

    test('enregistre puis relit la bibliothèque', () async {
      final dir = await Directory.systemTemp.createTemp('pazulu_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = LibraryStore(dir);
      await store.save(sample());
      await store.save(sample()); // deuxième écriture : copie de secours créée
      final loaded = await store.load();
      expect(loaded.warning, isNull);
      expect(loaded.data.entries.length, 1);
      expect(loaded.data.entries['mangadex:abc']!.progress.lastKey, '5');
    });

    test('utilise la copie de secours si le fichier est endommagé', () async {
      final dir = await Directory.systemTemp.createTemp('pazulu_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = LibraryStore(dir);
      await store.save(sample());
      await store.save(sample());
      await File('${dir.path}${Platform.pathSeparator}library.json').writeAsString('{corrompu');
      final loaded = await store.load();
      expect(loaded.warning, isNotNull);
      expect(loaded.data.entries.length, 1);
    });

    test('sauvegarde .pazulu : intégrité vérifiée', () {
      final text = LibraryStore.encodeBackup(sample(), '0.1.0');
      final back = LibraryStore.decodeBackup(text);
      expect(back.entries.length, 1);

      final tampered = text.replaceFirst('Titre', 'Pirate');
      expect(() => LibraryStore.decodeBackup(tampered), throwsFormatException);
      expect(() => LibraryStore.decodeBackup('{}'), throwsFormatException);
    });

    test('la fusion ne perd jamais de chapitres lus', () {
      final current = sample();
      final incoming = sample();
      incoming.entries['mangadex:abc']!.progress.readKeys = {'5', '6'};
      incoming.entries['mangadex:abc']!.updatedAt =
          DateTime.now().add(const Duration(minutes: 1));
      final report = LibraryStore.merge(current, incoming);
      expect(report.updated, 1);
      expect(
        current.entries['mangadex:abc']!.progress.readKeys,
        {'1', '2', '3', '4', '5', '6'},
      );
    });
  });

  group('CBZ', () {
    test('écrit puis relit une archive', () {
      final zip = writeZip([
        ZipEntry('001.jpg', Uint8List.fromList([1, 2, 3])),
        ZipEntry('002.png', Uint8List.fromList(List.generate(1000, (i) => i % 256))),
      ]);
      final back = readZip(zip);
      expect(back.map((e) => e.name), ['001.jpg', '002.png']);
      expect(back.first.data, [1, 2, 3]);
      expect(back.last.data.length, 1000);
    });

    test('crc32 conforme', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
    });
  });
}
