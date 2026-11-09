import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_consensus.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/models.dart';

SourceChapter ch(String source, num n, {DateTime? at}) => SourceChapter(
    sourceId: source, chapterId: '$source-$n', key: ChapterKey.parse('$n'), lang: 'en',
    group: source, pages: 10, publishedAt: at);

void main() {
  final now = DateTime(2026, 11, 9);
  // Real weekly release: 319 four days ago.
  DateTime real(int n) => DateTime(2026, 11, 5).subtract(Duration(days: 7 * (319 - n)));

  test('Catastrophic Necromancer : sites rapides et exacts gardés, 319 visible', () {
    final all = [
      // Copy sites: everything uploaded late, dated in bulk, stop at 317.
      for (final s in ['linkmanga', 'aqua', 'zin'])
        for (var n = 250; n <= 317; n++) ch(s, n, at: DateTime(2026, 10, 28)),
      // Accurate sites: real dates, already at 319 (one at 318).
      for (var n = 250; n <= 319; n++) ch('mangaread', n, at: real(n)),
      for (var n = 250; n <= 318; n++) ch('mangadex', n, at: real(n)),
    ];
    final (out, notes) = ChapterConsensus.apply(all, now: now);
    expect(out.any((c) => c.sourceId == 'mangaread'), isTrue);
    expect(out.any((c) => c.sourceId == 'mangadex'), isTrue);
    expect(out.any((c) => c.key.id == '319'), isTrue);
    expect(notes.where((n) => n.message.contains('AVANT')), isEmpty);
    // 319 only on one site, but a fresh release following 318: confirmed.
    expect(ChapterConsensus.unconfirmedAhead(out, now: now), isEmpty);
  });

  test('« 195 » ancien sur un seul site (Mythic Item) : toujours non confirmé', () {
    final old = DateTime(2026, 6, 1);
    final all = [
      for (final s in ['a', 'b', 'c']) for (var n = 150; n <= 194; n++) ch(s, n, at: old),
      for (var n = 150; n <= 195; n++) ch('aqua', n, at: old),
    ];
    expect(ChapterConsensus.unconfirmedAhead(all, now: now), {'en|195'});
  });
}
