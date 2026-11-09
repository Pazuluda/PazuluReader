import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/engine/identity/listing_guard.dart';

SourceChapter ch(String key) => SourceChapter(sourceId: 's', chapterId: 's-$key',
    key: ChapterKey.parse(key), lang: 'fr', group: 's', pages: 3);

void main() {
  test('Solo Leveling SushiScan (volumes, ch. 0, puis 179.5–200) : une seule œuvre', () {
    final list = [
      for (var v = 1; v <= 15; v++) ch('Volume $v'),
      ch('0'),
      ch('179.5'),
      for (var i = 180; i <= 200; i++) ch('$i'),
    ];
    expect(ListingGuard.looksMixed(list), isFalse);
  });

  test('page d\'accueil d\'un site (240, 877, 3862) : toujours refusée', () {
    expect(ListingGuard.looksMixed([ch('240'), ch('877'), ch('3862')]), isTrue);
  });

  test('connecteur lisant une série par identifiant : pas de contrôle « mélangé »', () {
    final scattered = [ch('240'), ch('241'), ch('877'), ch('878'), ch('3862')];
    expect(ListingGuard.rejectReason(scattered, const [], checkMixed: false), isNull);
    expect(ListingGuard.rejectReason(scattered, const []), isNotNull);
  });

  test('liste réelle d\'un site : 1–3 en aperçu puis 150–200 (pas un mélange)', () {
    final list = [ch('1'), ch('2'), ch('3'), for (var i = 150; i <= 200; i++) ch('$i')];
    expect(ListingGuard.looksMixed(list), isFalse);
  });

  test('série déplacée avec suffixe aléatoire (AsuraScans) : même page', () {
    expect(ListingGuard.samePage(Uri.parse('https://asura.example/series/solo-leveling-1f2e3d4c/'),
        Uri.parse('https://asura.example/comics/solo-leveling-ab39de10')), isTrue);
    expect(ListingGuard.samePage(Uri.parse('https://asura.example/series/solo-leveling-1f2e3d4c/'),
        Uri.parse('https://asura.example/comics/martial-peak-ab39de10')), isFalse);
  });
}
