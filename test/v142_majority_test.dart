import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/engine/identity/listing_guard.dart';

final now = DateTime(2026, 11, 15);

List<SourceChapter> site(String id, int to, {String lang = 'en', DateTime? last, DateTime? all}) => [
      for (var i = 1; i <= to; i++)
        SourceChapter(sourceId: id, chapterId: '$id-$i', key: ChapterKey.parse('$i'),
            lang: lang, group: id, pages: 3,
            publishedAt: all ?? (last?.subtract(Duration(days: 7 * (to - i))))),
    ];

String nameOf(String id) => id.startsWith('king') ? 'kingofshojo' : id;

void main() {
  test('Solo Leveling: Ragnarok : le roman (≈200 ch.) sur 2 sites contre le webtoon (75) '
      'sur 4 sites à jour → le roman est écarté', () {
    final june = DateTime(2026, 6, 5);
    final lists = {
      'king1': site('king1', 182),
      'king2': site('king2', 182),
      'arenascan': site('arenascan', 201, all: june),
      'manganato': site('manganato', 75, last: now.subtract(const Duration(days: 4))),
      'mangabats': site('mangabats', 75, last: now.subtract(const Duration(days: 4))),
      'mangakakalot': site('mangakakalot', 75),
      'mangaread': site('mangaread', 74),
      'en-hijala': site('en-hijala', 26),
      'mangas-origines': site('mangas-origines', 73, lang: 'fr'),
    };
    final out = ListingGuard.minorityLevels(lists, siteOf: nameOf, now: now);
    expect(out.keys.toSet(), {'king1', 'king2', 'arenascan'});
  });

  test('sites rapides à jour contre copies abandonnées : rien n\'est écarté', () {
    final old = now.subtract(const Duration(days: 300));
    final lists = {
      'a': site('a', 200, last: now.subtract(const Duration(days: 3))),
      'b': site('b', 199, last: now.subtract(const Duration(days: 3))),
      'c': site('c', 75, last: old),
      'd': site('d', 75, last: old),
      'e': site('e', 74, last: old),
    };
    expect(ListingGuard.minorityLevels(lists, siteOf: (id) => id, now: now), isEmpty);
  });

  test('page ouverte par l\'utilisateur : vote mais jamais écartée', () {
    final lists = {
      'x': site('x', 200),
      'a': site('a', 75, last: now),
      'b': site('b', 75, last: now),
      'c': site('c', 74, last: now),
    };
    expect(ListingGuard.minorityLevels(lists, siteOf: (id) => id, protect: {'x'}, now: now), isEmpty);
    expect(ListingGuard.minorityLevels(lists, siteOf: (id) => id, now: now).keys.toList(), ['x']);
  });

  test('moins de 4 sites : pas de vote', () {
    final lists = {'x': site('x', 200), 'a': site('a', 75, last: now), 'b': site('b', 75, last: now)};
    expect(ListingGuard.minorityLevels(lists, siteOf: (id) => id, now: now), isEmpty);
  });
}
