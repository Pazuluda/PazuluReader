import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pazulu_reader/core/sources/peppercarrot.dart';

void main() {
  test('two-language catalogue and lazy page URL construction', () async {
    var indexRequests = 0;
    final client = MockClient((request) async {
      expect(request.url.path, '/0_sources/episodes.json');
      indexRequests++;
      return http.Response(jsonEncode([
        {
          'name': 'ep01_Potion-of-Flight',
          'total_pages': 8,
          'translated_languages': ['en', 'fr', 'de'],
        },
        {
          'name': 'ep02_Rainbow-potions',
          'total_pages': 9,
          'translated_languages': ['en'],
        },
      ]), 200, headers: {'content-type': 'application/json'});
    });
    final source = PepperCarrotSource(client: client);
    final results = await source.search('Pepper');
    final info = await source.getWork('peppercarrot');
    expect(results.single.id, info.id);
    expect(info.description, isNotEmpty);
    expect(indexRequests, 0); // Covers/summaries do not download chapter pages.

    final chapters = await source.listChapters('peppercarrot', langs: ['en', 'fr']);
    expect(chapters.length, 3);
    expect(indexRequests, 1);
    final fr = chapters.singleWhere((c) => c.lang == 'fr');
    final pages = await source.getPages(fr);
    expect(pages.length, 9); // includes last credits page, as documented
    expect(pages.first.url, contains('/ep01_Potion-of-Flight/low-res/fr_'));
    expect(pages.first.url, endsWith('E01P00.jpg'));
    expect(pages.last.url, endsWith('E01P08.jpg'));
    expect(indexRequests, 1); // getPages only builds addresses
    client.close();
  });
}
