import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/anime/anilist.dart';
import 'package:pazulu_reader/core/anime/crunchyroll.dart';
import 'package:pazulu_reader/core/anime/fr_planning.dart';

// Same structure as the real page (cards with data-* attributes).
String _card(String nom, int? ts, String lang, {String type = 'Anime', String extra = '', String info = 'Saison 1'}) =>
    '<div class="as-carte planning-card $type $lang $extra" data-nom="$nom" '
    '${ts == null ? '' : 'data-release-ts="$ts"'} data-card-type="$type" data-carte-langue="$lang">'
    '<a><div class="as-carte-texte"><h3>$nom</h3><div class="as-carte-info"><span>$info</span>'
    '<span class="as-carte-temps">14h50</span></div></div></a></div>';

void main() {
  final jp = DateTime(2026, 11, 9, 15, 30); // Japanese airing (local time)
  final frTs = DateTime(2026, 11, 9, 16, 50).millisecondsSinceEpoch ~/ 1000;
  final page = '<html><body><div id="planningClass">'
      '${_card('Psyren', frTs, 'VOSTFR')}'
      '${_card('Psyren', frTs + 3600, 'VF')}'
      '${_card('Solo Leveling', frTs, 'VF', type: 'Scans')}'
      '${_card('Helluva Boss', null, 'VF', extra: 'pl-reporte', info: 'Saison 3?')}'
      '</div></body></html>';

  test('parse : animés seulement, heure, langue, reporté', () {
    final list = FrPlanning.parse(page);
    expect(list.length, 3);
    expect(list.first.title, 'Psyren');
    expect(list.first.lang, 'VOSTFR');
    expect(list.first.label, 'Saison 1');
    expect(list.first.at, DateTime(2026, 11, 9, 16, 50));
    expect(list.last.postponed, isTrue);
    expect(list.last.at, isNull);
  });

  test('normalize et correspondance de titres', () {
    expect(FrPlanning.normalize('Tensei Goblin Dakedo Shitsumon Aru?'), 'tensei goblin dakedo shitsumon aru');
    expect(FrPlanning.normalize('Les Carnets de l’Apothicaire'), 'les carnets de l apothicaire');
    expect(FrPlanning.sameWork('psyren', {'psyren'}), isTrue);
    expect(FrPlanning.sameWork('one piece', {'one punch man'}), isFalse);
    expect(FrPlanning.sameWork('the apothecary diaries', {'the apothecary diaries season 3'}), isTrue);
  });

  test('releaseFor : VOSTFR préféré, fenêtre autour de la diffusion japonaise', () {
    final fr = FrPlanning(FrPlanning.parse(page));
    const info = AnimeInfo(id: 1, title: 'PSYREN', altTitles: ['Psyren']);
    expect(fr.releaseFor(info, jp)?.lang, 'VOSTFR');
    expect(fr.releaseFor(info, jp.subtract(const Duration(days: 4))), isNull);
    const other = AnimeInfo(id: 2, title: 'Autre');
    expect(fr.releaseFor(other, jp), isNull);
    expect(fr.postponed(const AnimeInfo(id: 3, title: 'Helluva Boss')), isTrue);
  });

  test('Crunchyroll : heure France = planning - 20 min ; « sorti » selon la France', () {
    final fr = FrPlanning(FrPlanning.parse(page));
    const info = AnimeInfo(id: 1, title: 'Psyren', streaming: [
      StreamingLink(site: 'Crunchyroll', url: 'https://www.crunchyroll.com/series/X'),
    ]);
    expect(Crunchyroll.frenchTime(fr, info, jp), DateTime(2026, 11, 9, 16, 30));
    final airing = AnimeAiring(mediaId: 1, episode: 3, airingAt: jp);
    // Aired in Japan but not yet out in France: not listed.
    expect(Crunchyroll.fresh([(airing, info)], now: DateTime(2026, 11, 9, 16, 0), fr: fr), isEmpty);
    final out = Crunchyroll.fresh([(airing, info)], now: DateTime(2026, 11, 9, 17, 0), fr: fr);
    expect(out.single.french, isTrue);
    expect(out.single.airedAt, DateTime(2026, 11, 9, 16, 30));
    expect(out.single.jpAt, jp);
  });
}
