import 'models.dart';

/// Detects an incomplete chapter list: chapters known to exist (a later
/// chapter seen somewhere, or the last chapter announced by the metadata)
/// but missing from the readers attached so far.
class Coverage {
  /// Size of a hole that cannot be a mere numbering quirk.
  static const int gap = 5;

  /// Numbers of the missing chapters ranges, e.g. [(199, 261)].
  static List<(int, int)> holes(Iterable<SourceChapter> chapters, {String? lastChapter}) {
    final numbers = <int>{
      for (final c in chapters)
        if (!c.isExternal && c.key.number != null && c.key.number! >= 1) c.key.number!.floor(),
    }.toList()
      ..sort();
    final out = <(int, int)>[];
    for (var i = 0; i + 1 < numbers.length; i++) {
      if (numbers[i + 1] - numbers[i] > gap) out.add((numbers[i] + 1, numbers[i + 1] - 1));
    }
    final announced = double.tryParse((lastChapter ?? '').trim());
    final max = numbers.isEmpty ? 0 : numbers.last;
    if (announced != null && announced.floor() - max > gap) {
      out.add((max + 1, announced.floor()));
    }
    return out;
  }

  static bool incomplete(Iterable<SourceChapter> chapters, {String? lastChapter}) =>
      holes(chapters, lastChapter: lastChapter).isNotEmpty;
}
