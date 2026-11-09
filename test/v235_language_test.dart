import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/chapter_key.dart';
import 'package:pazulu_reader/core/language_consensus.dart';
import 'package:pazulu_reader/core/models.dart';

SourceChapter ch(String key, String source, String lang) => SourceChapter(
    sourceId: source, chapterId: '$source-$lang-$key', key: ChapterKey.parse(key),
    lang: lang, group: source, pages: 10);

void main() {
  test('FR annoncé par un seul site, en avance sur les autres FR : « FR ? »', () {
    final all = [
      for (var i = 220; i <= 229; i++) ch('$i', 'mangazin', 'en'),
      for (var i = 220; i <= 225; i++) ch('$i', 'sushiscan', 'fr'),
      for (var i = 225; i <= 229; i++) ch('$i', 'lelmanga', 'fr'),
    ];
    final doubt = LanguageConsensus.unconfirmed(all);
    expect(doubt, {'lelmanga-fr-226', 'lelmanga-fr-227', 'lelmanga-fr-228', 'lelmanga-fr-229'});
  });

  test('confirmé dès qu\'une deuxième source FR a le chapitre', () {
    final all = [
      ch('229', 'mangazin', 'en'),
      for (var i = 220; i <= 229; i++) ch('$i', 'sushiscan', 'fr'),
      for (var i = 225; i <= 229; i++) ch('$i', 'lelmanga', 'fr'),
    ];
    expect(LanguageConsensus.unconfirmed(all), isEmpty);
  });

  test('notifications : sortie FR d\'un seul site en avance ignorée', () {
    final e = LibraryEntry(work: const WorkInfo(id: 'w', title: 'W'));
    e.observedChapters['mangazin|en'] = [for (var i = 220; i <= 229; i++) '$i'];
    e.observedChapters['sushiscan|fr'] = [for (var i = 220; i <= 225; i++) '$i'];
    e.observedChapters['lelmanga|fr'] = [for (var i = 225; i <= 229; i++) '$i'];
    expect(LanguageConsensus.aheadOfPeers(e, 'lelmanga', 'fr', '228'), isTrue);
    expect(LanguageConsensus.aheadOfPeers(e, 'sushiscan', 'fr', '225'), isFalse);
    expect(LanguageConsensus.heldBySingleSourceAhead(e, 'fr', '229'), isTrue);
    expect(LanguageConsensus.heldBySingleSourceAhead(e, 'fr', '225'), isFalse);
  });
}
