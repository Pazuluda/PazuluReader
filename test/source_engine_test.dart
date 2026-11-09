import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/page_inspection.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/source_extensions.dart';

void main() {
  test('13 active, 2 archived, 15 historical profiles', () {
    final manager = SourceRecipeRegistry.defaults();
    expect(catalogSites.length, 13);
    expect(archivedCatalogSites.length, 2);
    expect(manager.all.length, 15);
    expect(manager.forSite('mangadex').mode, 'native');
    expect(manager.forSite('webtoon_fr').mode, 'official');
    expect(manager.forSite('aethonwebcomics').canInspect, false);
    expect(manager.forSite('manhwaclan').canInspect, true);
  });

  test('generic script inspects DOM only, and never fetches URLs', () {
    final js = makeInspectionScript(SourceRecipeRegistry.defaults().forSite('asurascans'));
    expect(js, contains('querySelectorAll'));
    expect(js, contains('data-src'));
    expect(js, isNot(contains('fetch(')));
    expect(js, isNot(contains('XMLHttpRequest')));
  });

  test('page inspection deduplicates and rejects local/private/non HTTPS images', () {
    final site = catalogSiteById('manhwaclan')!;
    final imageList = [
      'https://cdn.example.org/1.jpg',
      'https://cdn.example.org/1.jpg',
      'https://cdn.example.org/2.jpg',
      'http://cdn.example.org/3.jpg',
      'https://127.0.0.1/secret',
    ];
    final decoded = PageInspection.fromBrowser(jsonEncode({
      'url': 'https://manhwaclan.com/chapter-1',
      'title': 'Chapter 1',
      'images': imageList,
    }), site);
    expect(decoded.pages, ['https://cdn.example.org/1.jpg', 'https://cdn.example.org/2.jpg']);
    expect(() => PageInspection.fromBrowser(jsonEncode({
      'url': 'https://evil.example/chapter-1',
      'images': imageList,
    }), site), throwsFormatException);
  });

  test('partial source updates remain atomic, can update selectors', () {
    final manager = SourceRecipeRegistry.defaults();
    final before = manager.forSite('manhwaclan');
    expect(manager.mergeManifest(jsonEncode({
      'format': 'pazulu-source-recipes', 'schemaVersion': 1,
      'recipes': [{
        ...before.toJson(),
        'version': 2,
        'selectors': ['.custom-reader img'],
      }],
    })), 1);
    expect(manager.forSite('manhwaclan').version, 2);
    expect(manager.forSite('manhwaclan').selectors, ['.custom-reader img']);
    expect(() => manager.mergeManifest(jsonEncode({
      'format': 'pazulu-source-recipes', 'schemaVersion': 1,
      'recipes': [
        {'id': 'manhwaclan', 'version': 3, 'mode': 'inspect',
         'selectors': ['.ok img']},
        {'id': 'webtoon_fr', 'version': 3, 'mode': 'inspect',
         'selectors': ['.wrong img']},
      ],
    })), throwsFormatException);
    expect(manager.forSite('manhwaclan').version, 2);
  });

  test('new domains can be imported manually for generic sources only', () {
    final manager = SourceRecipeRegistry.defaults();
    final old = manager.forSite('manhwaclan');
    manager.mergeManifest(jsonEncode({
      'format': 'pazulu-source-recipes', 'schemaVersion': 1,
      'recipes': [{
        ...old.toJson(), 'version': 2,
        'hostAliases': ['manhwaclan.example'],
        'homeOverride': 'https://manhwaclan.example/',
      }],
    }));
    final changed = manager.forSite('manhwaclan');
    expect(changed.accepts(catalogSiteById('manhwaclan')!,
        'https://manhwaclan.example/chapter/3'), true);
    expect(changed.accepts(catalogSiteById('manhwaclan')!,
        'https://malicious.example/chapter/3'), false);
  });
}
