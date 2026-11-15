import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/engine/identity/listing_guard.dart';

List<SourceChapter> site(String id, int from, int to, {String lang = 'en'}) => [
      for (var i = from; i <= to; i++)
        SourceChapter(sourceId: id, chapterId: '$id-$i', key: ChapterKey.parse('$i'),
            lang: lang, group: id, pages: 3),
    ];

void main() {
  test('Solo Leveling: Ragnarok : une liste complète de 201 chapitres alors que tous '
      'les autres sites s\'arrêtent vers 73 = autre œuvre', () {
    final fake = site('arenascan', 1, 201);
    final reason = ListingGuard.farBeyondAllPeers(fake, [
      site('a', 1, 73),
      site('b', 1, 72),
      site('c', 1, 73, lang: 'fr'),
    ]);
    expect(reason, isNotNull);
    expect(reason, contains('201'));
    // La liste est pourtant complète : l'ancien contrôle la laissait passer.
    expect(ListingGuard.rejectReason(fake, [...site('a', 1, 73), ...site('b', 1, 72)]), isNull);
  });

  test('un seul autre site au même niveau suffit à garder la liste', () {
    expect(ListingGuard.farBeyondAllPeers(site('x', 1, 201), [
      site('a', 1, 73),
      site('b', 1, 199),
    ]), isNull);
  });

  test('site un peu en avance (nouvelles sorties) : gardé', () {
    expect(ListingGuard.farBeyondAllPeers(site('x', 1, 80), [site('a', 1, 73), site('b', 1, 74)]),
        isNull);
  });

  test('moins de 2 autres sites de la langue : pas de jugement', () {
    expect(ListingGuard.farBeyondAllPeers(site('x', 1, 201), [site('a', 1, 73)]), isNull);
    // Les sites FR ne jugent pas une liste EN (le français suit avec du retard).
    expect(ListingGuard.farBeyondAllPeers(site('x', 1, 201),
        [site('a', 1, 73, lang: 'fr'), site('b', 1, 70, lang: 'fr')]), isNull);
  });
}
