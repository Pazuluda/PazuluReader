import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/sources/sushiscan.dart';
import 'package:pazulu_reader/core/visible_pages.dart';

void main() {
  const chapterUrl = 'https://sushiscan.net/solo-leveling-vol-2/';

  test('SushiScan prend data-srcset même quand src est un placeholder', () {
    final pages = SushiScanSource.parsePages('''
    <div id="readerarea">
      <img src="/wp-content/themes/sushiscan/assets/img/readerarea.svg"
        data-srcset="https://cdn.example.org/images/page1.webp 1x, https://cdn.example.org/images/page1@2x.webp 2x">
      <picture><source srcset="https://cdn.example.org/images/page2.avif 1x"></picture>
      <img src="https://cdn.example.org/images/page3.jpg">
      <img src="/wp-content/themes/sushiscan/assets/img/readerarea.svg">
    </div>
    <img src="https://cdn.example.org/banner.jpg">
    ''', chapterUrl);
    expect(pages.map((e) => e.url), [
      'https://cdn.example.org/images/page1.webp',
      'https://cdn.example.org/images/page2.avif',
      'https://cdn.example.org/images/page3.jpg',
    ]);
  });

  test('Lecture DOM accepte pages visibles mais pas publicités / doublons / réseaux locaux', () {
    final payload = jsonEncode({
      'url': chapterUrl,
      'images': [
        'https://cdn.example.org/p1.webp',
        'https://cdn.example.org/p1.webp',
        'https://cdn.example.org/p2.avif',
        'https://localhost/internal.png',
        'https://acceptable.a-ads.com/ad.png',
        'https://cdn.example.org/readerarea.svg',
      ],
    });
    final pages = VisibleReaderPages.parse(payload, chapterUrl: chapterUrl);
    expect(pages.length, 2);
    expect(pages.first, isA<PageRef>());
  });

  test('DOM refuse un chapitre d’un autre domaine', () {
    expect(() => VisibleReaderPages.parse(jsonEncode({
      'url': 'https://other.example/solo-leveling-vol-2/',
      'images': ['https://cdn.example.org/p1.webp'],
    }), chapterUrl: chapterUrl), throwsFormatException);
  });
}
