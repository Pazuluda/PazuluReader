import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/anime/anilist.dart';
import 'package:pazulu_reader/core/anime/crunchyroll.dart';

AnimeInfo _anime(int id, {List<StreamingLink> links = const [], List<EpisodeLink> eps = const []}) =>
    AnimeInfo(id: id, title: 'A$id', streaming: links, episodeLinks: eps);

const _cr = StreamingLink(site: 'Crunchyroll', url: 'https://www.crunchyroll.com/series/GXJHM3NJ5/x');
const _adn = StreamingLink(site: 'ADN', url: 'https://animationdigitalnetwork.com/video/x');

void main() {
  test('EpisodeLink.numberOf lit les titres AniList', () {
    expect(EpisodeLink.numberOf('Episode 12 - The End'), 12);
    expect(EpisodeLink.numberOf('Épisode 3'), 3);
    expect(EpisodeLink.numberOf('Ep. 4 - x'), 4);
    expect(EpisodeLink.numberOf('Special'), isNull);
  });

  test('AniList : streamingEpisodes parsés', () {
    final info = AnimeInfo.fromJson({
      'id': 1,
      'title': {'romaji': 'X'},
      'externalLinks': [
        {'site': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/A', 'type': 'STREAMING'},
      ],
      'streamingEpisodes': [
        {'title': 'Episode 2 - B', 'url': 'https://www.crunchyroll.com/watch/E2', 'site': 'Crunchyroll'},
        {'title': 'Recap', 'url': 'https://www.crunchyroll.com/watch/R', 'site': 'Crunchyroll'},
        {'title': 'Episode 3', 'url': 'javascript:alert(1)', 'site': 'x'},
      ],
    })!;
    expect(info.episodeLinks.map((e) => e.number), [2]);
    expect(Crunchyroll.isOn(info), isTrue);
    expect(Crunchyroll.urlFor(info, episode: 2), 'https://www.crunchyroll.com/watch/E2');
    expect(Crunchyroll.urlFor(info, episode: 5), 'https://www.crunchyroll.com/series/A');
  });

  test('isOn : seulement Crunchyroll', () {
    expect(Crunchyroll.isOn(_anime(1, links: [_adn])), isFalse);
    expect(Crunchyroll.isOn(_anime(1, links: [_adn, _cr])), isTrue);
    expect(Crunchyroll.isCrunchyrollUrl('https://crunchyroll.com.evil.io/x'), isFalse);
  });

  test('fresh : 3 derniers jours, Crunchyroll, plus récent en premier, sans doublon', () {
    final now = DateTime(2026, 11, 9, 15);
    final cr = _anime(1, links: [_cr]);
    final cr2 = _anime(2, links: [_cr]);
    final adn = _anime(3, links: [_adn]);
    AnimeAiring a(int id, int ep, Duration ago) =>
        AnimeAiring(mediaId: id, episode: ep, airingAt: now.subtract(ago));
    final list = Crunchyroll.fresh([
      (a(1, 5, const Duration(hours: 30)), cr),
      (a(2, 8, const Duration(hours: 2)), cr2),
      (a(2, 8, const Duration(hours: 2)), cr2),
      (a(3, 1, const Duration(hours: 1)), adn),
      (a(1, 4, const Duration(days: 4)), cr),
      (a(1, 6, const Duration(hours: -3)), cr),
    ], now: now);
    expect([for (final f in list) '${f.info.id}:${f.episode}'], ['2:8', '1:5']);
    expect(list.first.url, _cr.url);
  });
}
