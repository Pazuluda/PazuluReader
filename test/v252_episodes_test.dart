import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/anime/anilist.dart';
import 'package:pazulu_reader/core/anime/crunchyroll.dart';

void main() {
  test('isEpisodeUrl : page d’épisode seulement', () {
    expect(Crunchyroll.isEpisodeUrl('https://www.crunchyroll.com/fr/watch/GXXX/slug'), isTrue);
    expect(Crunchyroll.isEpisodeUrl('https://www.crunchyroll.com/series/GYYY/slug'), isFalse);
    expect(Crunchyroll.isEpisodeUrl('https://evil.io/watch/x'), isFalse);
  });

  test('script de recherche : numéro et indices injectés, pas de navigation', () {
    final js = Crunchyroll.findEpisodeScript(6, hints: {'season': 2, 'titles': ['Black Clover Season 2']});
    expect(js, contains('})(6, {"season":2,"titles":["Black Clover Season 2"]})'));
    expect(js, contains('erc-seasons-select'));
    expect(js, contains('show-more-btn'));
    expect(js.contains('location.href ='), isFalse);
    expect(js.contains('location.assign'), isFalse);
  });

  test('numéro de saison dans les titres AniList', () {
    expect(Crunchyroll.seasonNumber('Black Clover Season 2'), 2);
    expect(Crunchyroll.seasonNumber('Kaguya-sama: Love is War Season 3'), 3);
    expect(Crunchyroll.seasonNumber('Mushoku Tensei 2nd Season'), 2);
    expect(Crunchyroll.seasonNumber('Overlord III'), 3);
    expect(Crunchyroll.seasonNumber('Black Clover'), isNull);
    expect(Crunchyroll.seasonNumber('Shingeki no Kyojin: The Final Season'), isNull);
  });

  test('indices de saison', () {
    final info = AnimeInfo(id: 1, title: 'Black Clover Season 2', episodes: 13, status: 'RELEASING',
        nextAiring: AnimeAiring(mediaId: 1, episode: 7, airingAt: DateTime(2026, 11, 14)),
        relations: const [AnimeRelation(id: 2, title: 'Black Clover', relation: 'PREQUEL')]);
    final h = Crunchyroll.seasonHints(info);
    expect(h['season'], 2);
    expect(h['count'], 6);
    expect(h['sequel'], isTrue);
  });
}
