import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_consensus.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';

SourceChapter ch(String source, num n, {DateTime? at, String lang = 'en'}) => SourceChapter(
    sourceId: source, chapterId: '$source-$n', key: ChapterKey.parse('$n'), lang: lang,
    group: source, pages: 10, publishedAt: at);

List<SourceChapter> run(String source, int from, int to, {DateTime Function(int n)? date,
    String lang = 'en'}) => [
      for (var n = from; n <= to; n++) ch(source, n, at: date?.call(n), lang: lang),
    ];

void main() {
  final now = DateTime(2026, 11, 9);
  DateTime weekly(int n) => DateTime(2026, 11, 1).subtract(Duration(days: 7 * (195 - n)));

  test('« 203 » sans les chapitres 196–202 ni date récente : non montré', () {
    final all = [
      ...run('a', 150, 195), ...run('b', 150, 195), ...run('c', 150, 194),
      ...run('d', 150, 195), ...run('e', 150, 180), ch('e', 203), ch('f', 203),
      ...run('f', 150, 190),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.any((c) => c.key.id == '203'), isFalse);
    expect(out.any((c) => c.key.id == '195'), isTrue);
    expect(notes, isNotEmpty);
  });

  test('site vraiment en avance (196…203 tous listés) : gardé', () {
    final all = [
      ...run('a', 150, 195), ...run('b', 150, 195), ...run('c', 150, 195),
      ...run('fast', 150, 203),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.sourceId == 'fast').map((c) => c.key.id), contains('203'));
  });

  test('FR en retard sur l\'EN : jamais comparés', () {
    final all = [
      ...run('a', 1, 319), ...run('b', 1, 319), ...run('c', 1, 319),
      ...run('fr1', 1, 198, lang: 'fr'), ...run('fr2', 1, 306, lang: 'fr'),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.length, all.length);
  });

  test('numérotation décalée de +1 (dates) : site mis de côté', () {
    final all = [
      ...run('a', 170, 195, date: weekly), ...run('b', 170, 195, date: weekly),
      ...run('c', 170, 195, date: weekly),
      // « shift » calls « n+1 » the chapter released the day of everybody's n.
      for (var n = 170; n <= 195; n++) ch('shift', n + 1, at: weekly(n)),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.any((c) => c.sourceId == 'shift'), isFalse);
    expect(notes.single.message, contains('décalée'));
  });

  test('moins de 3 sources : rien n\'est retiré', () {
    final all = [...run('a', 1, 50), ch('b', 300)];
    expect(ChapterConsensus.apply(all, now: now).$1.length, all.length);
  });

  test('un seul site annonce le 195, 3 autres s\'arrêtent au 194 : non confirmé', () {
    final all = [
      ...run('a', 150, 194), ...run('b', 150, 194), ...run('c', 150, 194),
      ...run('aqua', 150, 195),
    ];
    expect(ChapterConsensus.unconfirmedAhead(all), {'en|195'});
  });

  test('deux sites ont le 195 : confirmé', () {
    final all = [
      ...run('a', 150, 194), ...run('b', 150, 195), ...run('c', 150, 194),
      ...run('aqua', 150, 195),
    ];
    expect(ChapterConsensus.unconfirmedAhead(all), isEmpty);
  });

  test('chapitre 90 découpé en 90.1…90.4 par 3 sites, entier ailleurs : morceaux masqués', () {
    final all = [
      ...run('asura', 85, 95), ...run('mangaread', 85, 95), ...run('district', 85, 95),
      for (final s in ['arena', 'kos', 'mangazin']) ...[
        ...run(s, 85, 95).where((c) => c.key.id != '90'),
        ch(s, 90.1), ch(s, 90.2), ch(s, 90.3), ch(s, 90.4),
      ],
      ch('mangazin', 90),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.any((c) => c.key.id.startsWith('90.')), isFalse);
    expect(out.where((c) => c.key.id == '90').length, 4);
    expect(notes.any((n) => n.message.contains('découpé')), isTrue);
  });

  test('un vrai 107.5 seul : jamais masqué', () {
    final all = [
      ...run('a', 100, 110), ...run('b', 100, 110), ...run('c', 100, 110),
      ch('a', 107.5), ch('b', 107.5),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.key.id == '107.5').length, 2);
  });

  test('morceaux que personne n\'a en entier : gardés', () {
    final all = [
      ...run('a', 1, 20).where((c) => c.key.id != '5'), ch('a', 5.1), ch('a', 5.2),
      ...run('b', 1, 20).where((c) => c.key.id != '5'), ch('b', 5.1), ch('b', 5.2),
      ...run('c', 1, 20).where((c) => c.key.id != '5'),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.key.id == '5.1').length, 2);
  });

  test('site au « 194 » daté 2 mois AVANT les autres (manganato) : numérotation différente, mis de côté', () {
    final bulk = DateTime(2026, 6, 12);
    final all = [
      for (final s in ['asura', 'mangaread', 'district'])
        ...run(s, 150, 194, date: (n) => DateTime(2026, 8, 25).subtract(Duration(days: 7 * (194 - n)))),
      // Copied in one day (12 June), and numbered ahead: 150 … 202.
      for (var n = 150; n <= 202; n++) ch('nato', n, at: bulk),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.any((c) => c.sourceId == 'nato'), isFalse);
    expect(notes.any((n) => n.message.contains('AVANT')), isTrue);
  });

  test('site qui a tout copié en un jour, après les autres : gardé', () {
    final all = [
      for (final s in ['asura', 'mangaread', 'district'])
        ...run(s, 150, 194, date: (n) => DateTime(2026, 8, 25).subtract(Duration(days: 7 * (194 - n)))),
      for (var n = 150; n <= 194; n++) ch('copy', n, at: DateTime(2026, 10, 22)),
    ];
    final (out, _) = ChapterConsensus.apply(all, now: now);
    expect(out.where((c) => c.sourceId == 'copy').length, 45);
  });
}
