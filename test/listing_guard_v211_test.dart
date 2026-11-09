import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';
import 'package:pazulu_reader/engine/identity/listing_guard.dart';

SourceChapter c(String number, String url, {String source = 'public_x'}) =>
    SourceChapter(sourceId: source, chapterId: url, key: ChapterKey.parse(number),
        lang: 'en', group: source);

List<SourceChapter> mangadexSoloLeveling() => [
      for (var i = 1; i <= 15; i++)
        SourceChapter(sourceId: 'mangadex', chapterId: 'md-$i', key: ChapterKey.parse('$i'),
            lang: 'en', group: 'g', externalUrl: 'https://webnovel.example/$i'),
      for (var i = 180; i <= 200; i++) c('$i', 'md-r$i', source: 'mangadex'),
    ];

void main() {
  group('Bug Solo Leveling : chapitres d\'autres œuvres', () {
    test('liste de la page d\'accueil (3862, 877, 240) : mélange détecté', () {
      final home = [
        c('3862', 'https://site.example/martial-peak/chapter-3862/'),
        c('3861', 'https://site.example/martial-peak/chapter-3861/'),
        c('877', 'https://site.example/tales-of-demons/chapter-877/'),
        c('876', 'https://site.example/tales-of-demons/chapter-876/'),
        c('240', 'https://site.example/other/chapter-240/'),
        c('239', 'https://site.example/other/chapter-239/'),
      ];
      expect(ListingGuard.looksMixed(home), isTrue);
      expect(ListingGuard.rejectReason(home, mangadexSoloLeveling()), isNotNull);
      expect(ListingGuard.belongingTo('https://site.example/manga/solo-leveling/', home),
          isEmpty);
    });

    test('vraie liste Solo Leveling : acceptée', () {
      final real = [
        for (var i = 0; i <= 200; i++)
          c('$i', 'https://site.example/manga/solo-leveling/chapter-$i/'),
      ];
      expect(ListingGuard.looksMixed(real), isFalse);
      expect(ListingGuard.rejectReason(real, mangadexSoloLeveling()), isNull);
      expect(ListingGuard.belongingTo('https://site.example/manga/solo-leveling/', real),
          hasLength(201));
    });

    test('site qui ne publie que les derniers chapitres : accepté', () {
      final recent = [
        for (var i = 150; i <= 201; i++) c('$i', 'https://s.example/solo-leveling-chapter-$i/'),
      ];
      expect(ListingGuard.rejectReason(recent, mangadexSoloLeveling()), isNull);
      expect(ListingGuard.belongingTo('https://s.example/manga/solo-leveling/', recent),
          hasLength(52));
    });

    test('numéros très au-delà de l\'œuvre connue : refusé', () {
      final other = [for (var i = 600; i <= 700; i++) c('$i', 'https://s.example/x/chapter-$i/')];
      expect(ListingGuard.rejectReason(other, mangadexSoloLeveling()), contains('700'));
    });

    test('Solo Leveling: Ragnarok n\'est pas Solo Leveling', () {
      final mixed = [
        c('5', 'https://s.example/solo-leveling-ragnarok-chapter-5/'),
        c('6', 'https://s.example/solo-leveling-chapter-6/'),
      ];
      final kept = ListingGuard.belongingTo('https://s.example/manga/solo-leveling/', mixed);
      expect(kept.map((x) => x.key.id), ['6']);
    });

    test('redirection vers l\'accueil ou une autre série : page différente', () {
      final asked = Uri.parse('https://s.example/manga/solo-leveling/');
      expect(ListingGuard.samePage(asked, Uri.parse('https://s.example/')), isFalse);
      expect(ListingGuard.samePage(asked,
          Uri.parse('https://s.example/manga/martial-peak/')), isFalse);
      expect(ListingGuard.samePage(asked,
          Uri.parse('https://new-domain.example/manga/solo-leveling')), isTrue);
    });

    test('carte de recherche dont le lien pointe vers une autre série : ignorée', () {
      expect(ListingGuard.slugAgreesWithTitle(
          'https://s.example/manga/martial-peak/', 'Solo Leveling'), isFalse);
      expect(ListingGuard.slugAgreesWithTitle(
          'https://s.example/manga/solo-leveling/', 'Solo Leveling'), isTrue);
      expect(ListingGuard.slugAgreesWithTitle(
          'https://s.example/series/12345', 'Solo Leveling'), isTrue);
      expect(ListingGuard.slugAgreesWithTitle(
          'https://s.example/manga/tensei-shitara-slime/',
          'Moi, quand je me réincarne en Slime'), isTrue);
    });
  });

  group('Connecteur universel protégé', () {
    const site = CatalogSite('directory_007', 'Site', 'https://site.example/', ['en'],
        SiteIntegration.website);
    const homePage = '''
<html><body><div class="page-item-detail">
 <a href="https://site.example/manga/martial-peak/">Martial Peak</a>
 <ul><li class="wp-manga-chapter"><a href="https://site.example/manga/martial-peak/chapter-3862/">Chapter 3862</a></li></ul>
</div><div class="page-item-detail">
 <a href="https://site.example/manga/tales-of-demons/">Tales of Demons</a>
 <ul><li class="wp-manga-chapter"><a href="https://site.example/manga/tales-of-demons/chapter-877/">Chapter 877</a></li></ul>
</div></body></html>''';

    test('la page d\'accueil reçue pour une fiche ne donne aucun chapitre', () async {
      final source = PublicCatalogSource(site, fetchHtml: (_) async => homePage);
      final chapters = await source.listChapters(
          'https://site.example/manga/solo-leveling/', langs: const ['en']);
      expect(chapters, isEmpty);
    });

    test('lien égaré d\'une autre série sur la fiche : retiré, le reste gardé', () async {
      const mixedSeriesPage = '''
<html><body><ul>
 <li class="wp-manga-chapter"><a href="https://site.example/manga/solo-leveling/chapter-3862/">Chapter 3862</a></li>
 <li class="wp-manga-chapter"><a href="https://site.example/manga/solo-leveling/chapter-200/">Chapter 200</a></li>
 <li class="wp-manga-chapter"><a href="https://site.example/manga/solo-leveling/chapter-199/">Chapter 199</a></li>
</ul></body></html>''';
      final source = PublicCatalogSource(site, fetchHtml: (_) async => mixedSeriesPage);
      final list = await source.listChapters('https://site.example/manga/solo-leveling/',
          langs: const ['en']);
      expect(list.map((c) => c.key.id).toSet(), {'199', '200'});
    });
  });

  test('type par défaut des fiches web conservé', () {
    expect(WorkInfo(id: 'x', title: 'x').type, ContentType.other);
  });
}
