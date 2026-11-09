import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/visible_pages.dart';
import 'package:pazulu_reader/ui/widgets/official_web_view.dart';

void main() {
  const chapter = 'https://sushiscan.net/solo-leveling-chap-179-5/';

  test('Le script du lecteur inspecte le DOM sans fetch ni navigation', () {
    expect(visiblePagesScript.contains('document.querySelectorAll'), isTrue);
    expect(visiblePagesScript.contains('#readerarea img'), isTrue);
    expect(visiblePagesScript.contains('window.fetch('), isFalse);
    expect(visiblePagesScript.contains('location.assign('), isFalse);
  });

  test('Deux URLs de planches deviennent deux pages natives ordonnees', () {
    final pages = VisibleReaderPages.parse(jsonEncode({
      'url': chapter,
      'images': [
        'https://images.example.org/001.webp',
        'https://images.example.org/002.webp',
      ],
    }), chapterUrl: chapter);
    expect(pages.length, 2);
    expect(pages[0].url, 'https://images.example.org/001.webp');
    expect(pages[1].url, 'https://images.example.org/002.webp');
  });

  test('Le chapitre ne peut pas etre remplace par une page hors domaine', () {
    expect(() => VisibleReaderPages.parse(jsonEncode({
      'url': 'https://inconnu.example/autre/',
      'images': ['https://images.example.org/page.webp'],
    }), chapterUrl: chapter), throwsFormatException);
  });

  test('La WebView accepte un mode invisible explicite', () {
    const browser = OfficialWebView(
      url: chapter,
      initiallyVisible: false,
      fallback: SizedBox.shrink(),
    );
    expect(browser.initiallyVisible, isFalse);
  });
}
