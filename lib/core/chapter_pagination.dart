import 'dart:convert';

import 'package:html/dom.dart' as dom;

import 'models.dart';
import 'visible_pages.dart';

/// Pagination published by a chapter reader. A single visible image is not
/// proof that a page-by-page chapter is finished.
class ChapterPagination {
  const ChapterPagination({required this.pages, this.total, this.current = 1,
    this.selectIndex});

  final List<PageRef> pages;
  final int? total;
  final int current;
  final int? selectIndex;

  bool get isPaged => total != null && total! > 1;
  bool get isIncomplete => isPaged && pages.length < total!;

  /// The site, not Pazulu, must provide the number of pages. Never fabricate
  /// image URLs by incrementing a filename.
  static ChapterPagination fromBrowser(Object result, {required String chapterUrl}) {
    dynamic value = result;
    for (var i = 0; i < 3 && value is String; i++) {
      value = jsonDecode(value);
    }
    if (value is! Map) {
      throw const FormatException('Réponse du navigateur invalide.');
    }
    final pages = VisibleReaderPages.parse(value, chapterUrl: chapterUrl);
    final raw = value['pagination'];
    if (raw is! Map) return ChapterPagination(pages: pages);
    final total = _safeCount(raw['total']);
    final current = _safeCount(raw['current']) ?? 1;
    final selectIndex = raw['selectIndex'];
    return ChapterPagination(pages: pages, total: total, current: current,
      selectIndex: selectIndex is int && selectIndex >= 0 && selectIndex < 50
          ? selectIndex : null);
  }

  static int? _safeCount(Object? value) => value is int && value >= 1 && value <= 300
      ? value : null;

  /// HTML-side early warning. A selector containing 14 numbered options means
  /// the single reader image cannot be returned as a complete 1/1 chapter.
  static int? totalFromHtml(dom.Document doc) {
    int? result;
    final selects = doc.querySelectorAll('select');
    for (final select in selects) {
      final description = '${select.attributes['id'] ?? ''} ${select.attributes['name'] ?? ''} '
          '${select.attributes['class'] ?? ''} ${select.parent?.attributes['class'] ?? ''}'.toLowerCase();
      final options = select.querySelectorAll('option');
      if (options.length < 2 || options.length > 300) continue;
      final numbers = <int>[];
      for (final option in options) {
        final label = option.text.trim();
        final match = RegExp(r'^(?:page\s*)?(\d+)(?:\s*/\s*\d+)?$', caseSensitive: false).firstMatch(label);
        if (match == null) break;
        numbers.add(int.parse(match.group(1)!));
      }
      if (numbers.length != options.length) continue;
      final ordered = numbers.toSet().length == numbers.length &&
          numbers.every((number) => number >= 1 && number <= options.length) &&
          numbers.contains(1) && numbers.contains(options.length);
      if (!ordered) continue;
      if (!RegExp(r'page|pagination|reader').hasMatch(description)) continue;
      if (result == null || options.length > result) result = options.length;
    }
    for (final node in doc.querySelectorAll(
        '.page-number, .page-numbers, .pagination, .page-select, '
        '#pageSelection, #page-select, .reader-pagination')) {
      // A <select> concatenates all <option> labels in its textContent.
      // '1/14' + '2/14' becomes '1/142/14' and must NOT be read as 142 pages.
      // Select options were already validated above one-by-one.
      if (node.localName == 'select' || node.querySelector('select') != null) continue;
      final match = RegExp(r'\b\d{1,3}\s*/\s*(\d{1,3})\b').firstMatch(node.text);
      final count = match == null ? null : int.tryParse(match.group(1)!);
      if (count != null && count > 1 && count <= 300 && (result == null || count > result)) {
        result = count;
      }
    }
    return result;
  }
}
