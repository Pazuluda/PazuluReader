import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/community_sources.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/suggested_sources.dart';

void main() {
  test('200 entries are mapped without duplicates of the 13 curated sites', () {
    final raw = File('assets/suggested_sources.json').readAsStringSync();
    final suggested = SuggestedSourceCatalog.parse(raw);
    expect(suggested, hasLength(200));
    final available = CommunitySourceDirectory.fromSuggestions(suggested);
    // Four of the 200 domains are already in the original 13.
    expect(available, hasLength(196));
    expect(catalogSites.length + available.length, 209);
    // WEBTOON FR/EN deliberately share a host but have separate languages.
    expect({...catalogSites.map((s) => Uri.parse(s.home).host),
      ...available.map((s) => Uri.parse(s.home).host)}.length, 208);
    expect(available.every((s) => !s.hasReaderConnector), isTrue);
    expect(available.any((s) => s.id == 'directory_001'), isTrue);
    expect(available.any((s) => s.id == 'directory_200'), isTrue);
  });

  test('a repeated suggestion never creates duplicate source IDs', () {
    final raw = File('assets/suggested_sources.json').readAsStringSync();
    final input = SuggestedSourceCatalog.parse(raw);
    final mapped = CommunitySourceDirectory.fromSuggestions([...input, input.first]);
    expect(mapped, hasLength(196));
    expect(mapped.map((s) => s.id).toSet().length, mapped.length);
  });
}
