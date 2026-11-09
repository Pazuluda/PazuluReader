import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/chapters.dart';
import 'package:pazulu_reader/core/discovery.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/engine/diagnostics/engine_log.dart';
import 'package:pazulu_reader/engine/discovery/discovery_engine.dart';
import 'package:pazulu_reader/engine/identity/canonical_chapter.dart';

SourceChapter ch(String label, {String source = 'a', String lang = 'en',
    String? volume}) {
  final (key, vol) = ChapterLabelParser.parse(label);
  return SourceChapter(sourceId: source, chapterId: '$source-$label', key: key,
      lang: lang, group: source, title: label, volume: volume ?? vol);
}

void main() {
  group('ChapterKey 2.0', () {
    test('Extra 1 n\'est jamais le chapitre 1', () {
      expect(ChapterKey.parse('Extra 1').id, 'extra-1');
      expect(ChapterKey.parse('Extra 1').isSpecial, isTrue);
      expect(ChapterKey.parse('Extra 1') == ChapterKey.parse('1'), isFalse);
      expect(ChapterKey.parse('Chapitre Extra 1').id, 'extra-1');
      expect(ChapterKey.parse('Bonus 2').id, 'bonus-2');
      expect(ChapterKey.parse('Side Story 3').id, 'side-story-3');
      expect(ChapterKey.parse('Épilogue').id, 'epilogue');
    });

    test('Volume 12 - Bonus reste distinct du volume 12', () {
      expect(ChapterKey.parse('Volume 12 - Bonus').id, 'volume-12-bonus');
      expect(ChapterKey.parse('Volume 12').id, 'volume-12');
      expect(ChapterKey.parse('Volume 12 - Bonus').longLabel, 'Volume 12 - Bonus');
    });

    test('décimales conservées : 115.1 ≠ 115.2 ≠ 115.10, 12.0 = 12', () {
      final a = ChapterKey.parse('115.1');
      final b = ChapterKey.parse('115.2');
      final c = ChapterKey.parse('115.10');
      expect(a == b, isFalse);
      expect(a == c, isFalse);
      expect(ChapterKey.parse('12.0'), ChapterKey.parse('12'));
      expect(ChapterKey.parse('012'), ChapterKey.parse('12'));
      final sorted = [c, b, a, ChapterKey.parse('115'), ChapterKey.parse('116')]..sort();
      expect(sorted.map((k) => k.id), ['115', '115.1', '115.10', '115.2', '116']);
    });

    test('le regroupement ne fusionne jamais extras, décimaux et chapitres', () {
      final groups = groupChapters([
        ch('Chapter 115'), ch('Chapter 115.1'), ch('Chapter 115.2'),
        ch('Chapter 115.5'), ch('Chapter 116'), ch('Chapter Extra 1'),
        ch('Volume 12 - Bonus'), ch('Chapter 1'),
      ]);
      expect(groups.length, 8);
    });
  });

  group('Lecture des libellés', () {
    test('un marqueur explicite l\'emporte sur un nombre du titre', () {
      expect(ChapterLabelParser.parse('Kaiju No. 8 Chapter 100').$1.id, '100');
      expect(ChapterLabelParser.parse('Solo Leveling Chapitre 115.1').$1.id, '115.1');
      final (key, volume) = ChapterLabelParser.parse('Vol.3 Ch.21');
      expect(key.id, '21');
      expect(volume, '3');
      expect(ChapterLabelParser.parse('Volume 12 - Bonus').$1.id, 'volume-12-bonus');
      expect(ChapterLabelParser.parse('Martial Peak Extra 2').$1.id, 'extra-2');
    });

    test('sans marqueur, le dernier nombre est retenu', () {
      expect(ChapterLabelParser.parse('Mob Psycho 100 - 45').$1.id, '45');
    });
  });

  group('Identité canonique et équivalences', () {
    test('115.1 n\'est jamais remplacé par 115.2', () {
      final a = CanonicalChapter.of(ch('Chapter 115.1'), edition: 'manga');
      final b = CanonicalChapter.of(ch('Chapter 115.2', source: 'b'), edition: 'manga');
      expect(a.compare(b), Equivalence.different);
    });

    test('même chapitre sur deux sources, langues différentes : exact', () {
      final a = CanonicalChapter.of(ch('Chapter 115.1'), edition: 'manga');
      final b = CanonicalChapter.of(ch('Chapitre 115.1', source: 'b', lang: 'fr'),
          edition: 'manga');
      expect(a.compare(b), Equivalence.exact);
    });

    test('roman et manga ne sont jamais équivalents', () {
      final manga = CanonicalChapter.of(ch('Chapter 140'), edition: 'manga');
      final novel = CanonicalChapter.of(ch('Chapter 140', source: 'b'), edition: 'novel');
      expect(manga.compare(novel), Equivalence.different);
    });

    test('manhwa et webtoon : même bande dessinée', () {
      final a = CanonicalChapter.of(ch('Chapter 10'), edition: 'manhwa');
      final b = CanonicalChapter.of(ch('Chapter 10', source: 'b'), edition: 'webtoon');
      expect(a.compare(b), Equivalence.exact);
    });

    test('Extra sans volume : confirmation demandée', () {
      final a = CanonicalChapter.of(ch('Extra 1'), edition: 'manga');
      final b = CanonicalChapter.of(ch('Extra 1', source: 'b'), edition: 'manga');
      expect(a.compare(b), Equivalence.needsConfirmation);
      final v1 = CanonicalChapter.of(ch('Extra 1', volume: '3'), edition: 'manga');
      final v2 = CanonicalChapter.of(ch('Extra 1', source: 'b', volume: '4'), edition: 'manga');
      expect(v1.compare(v2), Equivalence.different);
      final v3 = CanonicalChapter.of(ch('Extra 1', source: 'c', volume: 'Vol. 3'),
          edition: 'manga');
      expect(v1.compare(v3), Equivalence.exact);
    });

    test('même numéro, volumes explicites différents : confirmation', () {
      final a = CanonicalChapter.of(ch('Chapter 140', volume: '20'), edition: 'manga');
      final b = CanonicalChapter.of(ch('Chapter 140', source: 'b', volume: '31'),
          edition: 'manga');
      expect(a.compare(b), Equivalence.needsConfirmation);
    });
  });

  group('Découverte multisource', () {
    WorkInfo w(String title, {List<String> alt = const [], ContentType type =
        ContentType.manga, String source = 's', List<String> authors = const [],
        int? year}) =>
        WorkInfo(id: '$source:$title', title: title, altTitles: alt, type: type,
            authors: authors, year: year,
            links: [SourceLink(sourceId: source, workId: title)]);

    test('My Dress-Up Darling = Sono Bisque Doll wa Koi wo Suru (alias exact)', () {
      final en = w('My Dress-Up Darling', alt: ['Sono Bisque Doll wa Koi wo Suru'],
          source: 'mangadex');
      final jp = w('Sono Bisque Doll wa Koi wo Suru', source: 'other');
      expect(DiscoveryEngine.match(en, jp), MatchReason.exactAlias);
    });

    test('Slime : titres FR/EN/JP regroupés grâce aux alias, accents ignorés', () {
      final en = w('That Time I Got Reincarnated as a Slime',
          alt: ['Tensei Shitara Slime Datta Ken', 'Moi, quand je me réincarne en Slime'],
          source: 'mangadex');
      final fr = w('Moi, quand je me REINCARNE en slime', source: 'fr');
      final jp = w('Tensei shitara Slime Datta Ken', source: 'jp');
      final clusters = DiscoveryEngine(log: EngineLog()).group([en, fr, jp]);
      expect(clusters.length, 1);
      expect(clusters.single.merged.links.length, 3);
    });

    test('titres proches mais œuvres distinctes : jamais fusionnées', () {
      expect(DiscoveryEngine.match(w('Solo Leveling'), w('Solo Leveling: Ragnarok')),
          MatchReason.none);
      expect(DiscoveryEngine.match(w('Slime'), w('Slime', type: ContentType.novel)),
          MatchReason.none);
      expect(sameWorkAcrossSources(
          w('Tensei Shitara Slime Datta Ken'),
          w('Tensei Shitara Slime Datta Ken', type: ContentType.novel)), isFalse);
    });

    test('auteurs connus et différents : pas de fusion malgré un titre identique', () {
      expect(DiscoveryEngine.match(
          w('Blue Box', authors: ['Kouji Miura'], source: 'a'),
          w('Blue Box', authors: ['Someone Else'], source: 'b')), MatchReason.none);
      expect(DiscoveryEngine.match(
          w('Blue Box', year: 2021, source: 'a'),
          w('Blue Box', year: 1998, source: 'b')), MatchReason.none);
    });

    test('fiche d\'un site web (type inconnu) rattachée à la bande dessinée, jamais au roman', () {
      final site = w('Solo Leveling', type: ContentType.other, source: 'public_x');
      expect(DiscoveryEngine.match(w('Solo Leveling', type: ContentType.manhwa,
          source: 'mangadex'), site), MatchReason.exactAlias);
      expect(DiscoveryEngine.match(w('Solo Leveling', type: ContentType.novel,
          source: 'novel'), site), MatchReason.none);
      expect(mergeSearchResults([
        w('Solo Leveling', type: ContentType.manhwa, source: 'mangadex'), site,
      ]).length, 1);
    });

    test('compatibilité : mergeSearchResults conserve ses règles', () {
      final a = WorkInfo(id: 'a', title: 'Example', type: ContentType.manga);
      final b = WorkInfo(id: 'b', title: 'Example', type: ContentType.webtoon);
      expect(mergeSearchResults([a, b]).length, 2);
    });
  });
}
