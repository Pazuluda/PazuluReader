/// Clé canonique d'un chapitre, indépendante de la source.
///
/// "12", "12.0", "Ch. 12" et "12,0" donnent tous la clé "12".
/// Les chapitres sans numéro (one-shot, extra) gardent un identifiant texte.
///
/// Moteur 2.0 : les extras, bonus et chapitres spéciaux numérotés ne sont
/// PLUS confondus avec un chapitre ordinaire ("Extra 1" ≠ "1"), un bonus de
/// volume reste distinct du volume ("Volume 12 - Bonus" ≠ "Volume 12") et la
/// partie décimale est conservée telle qu'écrite ("115.10" ≠ "115.1"), seuls
/// les zéros d'une partie entièrement nulle sont retirés ("12.0" = "12").
class ChapterKey implements Comparable<ChapterKey> {
  const ChapterKey._(this.number, this.id);

  /// Numéro décimal, ou null pour un chapitre spécial.
  final double? number;

  /// Identifiant stable, utilisé pour la progression et la synchro.
  final String id;

  static final RegExp _numberPattern = RegExp(r'(\d+(?:\.\d+)?)');
  static final RegExp _chapterPrefix = RegExp(
      r'^(?:chapitre|chapter|chap\.?|ch\.?|episode|ep\.?)[\s:#._-]*',
      caseSensitive: false);
  static final RegExp _volumePattern = RegExp(
      r'^(?:volume|vol\.?|tome)[\s_-]*(\d+(?:\.\d+)?)',
      caseSensitive: false);
  static final RegExp _specialPattern = RegExp(
      r'^(extra|bonus|special|sp\.?|omake|side[\s_-]*story|hors[\s_-]*s[eé]rie|'
      r'prologue|[eé]pilogue|interlude|afterword|postface)(?![a-z])',
      caseSensitive: false);
  static final RegExp _bonusWords = RegExp(
      r'(?:^|[^a-z])(?:bonus|extra|special|omake|hors[\s_-]*s[eé]rie)(?![a-z])',
      caseSensitive: false);

  factory ChapterKey.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const ChapterKey._(null, 'oneshot');
    }
    final cleaned = raw.trim().replaceAll(',', '.');
    // Volumes are not chapters: do not merge Vol. 2 with Ch. 2.
    final volumeMatch = _volumePattern.firstMatch(cleaned);
    if (volumeMatch != null) {
      final n = _formatText(volumeMatch.group(1)!);
      final rest = cleaned.substring(volumeMatch.end);
      // "Volume 12 - Bonus" is extra material, never the volume itself.
      if (_bonusWords.hasMatch(rest)) {
        return ChapterKey._(null, 'volume-$n-bonus');
      }
      return ChapterKey._(null, 'volume-$n');
    }
    final withoutPrefix = cleaned.replaceFirst(_chapterPrefix, '');
    final special = _specialPattern.firstMatch(withoutPrefix);
    if (special != null) {
      final word = _specialWord(special.group(1)!);
      final tail = withoutPrefix.substring(special.end);
      final n = _numberPattern.firstMatch(tail);
      return ChapterKey._(null, n == null ? word : '$word-${_formatText(n.group(1)!)}');
    }
    final match = _numberPattern.firstMatch(cleaned);
    if (match == null) {
      return ChapterKey._(null, cleaned.toLowerCase());
    }
    final text = _formatText(match.group(1)!);
    return ChapterKey._(double.parse(text), text);
  }

  static String _specialWord(String raw) {
    final w = raw.toLowerCase().replaceAll(RegExp(r'[\s_.]+'), '-')
        .replaceAll('é', 'e');
    if (w.startsWith('side')) return 'side-story';
    if (w.startsWith('hors')) return 'hors-serie';
    if (w == 'sp' || w == 'sp-') return 'special';
    return w.replaceAll(RegExp(r'-+$'), '');
  }

  /// Keeps the written decimals ("115.10" stays "115.10") but removes an
  /// all-zero fraction and leading zeros ("012.0" -> "12").
  static String _formatText(String digits) {
    final parts = digits.split('.');
    var whole = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.isEmpty) whole = '0';
    if (parts.length < 2) return whole;
    final fraction = parts[1];
    if (RegExp(r'^0+$').hasMatch(fraction)) return whole;
    return '$whole.$fraction';
  }

  bool get isSpecial => number == null;

  /// Libellé court pour l'interface.
  String get label {
    if (number != null) return 'Ch. $id';
    if (id.startsWith('volume-')) {
      final rest = id.substring(7);
      return rest.endsWith('-bonus')
          ? 'Vol. ${rest.substring(0, rest.length - 6)} · Bonus'
          : 'Vol. $rest';
    }
    if (id == 'oneshot') return 'One-shot';
    return _specialLabel(id);
  }

  /// Libellé long pour les titres.
  String get longLabel {
    if (number != null) return 'Chapitre $id';
    if (id.startsWith('volume-')) {
      final rest = id.substring(7);
      return rest.endsWith('-bonus')
          ? 'Volume ${rest.substring(0, rest.length - 6)} - Bonus'
          : 'Volume $rest';
    }
    if (id == 'oneshot') return 'One-shot';
    return _specialLabel(id);
  }

  static String _specialLabel(String id) {
    final m = RegExp(r'^([a-z-]+?)-(\d+(?:\.\d+)?)$').firstMatch(id);
    final word = m?.group(1) ?? id;
    final pretty = switch (word) {
      'extra' => 'Extra',
      'bonus' => 'Bonus',
      'special' => 'Spécial',
      'omake' => 'Omake',
      'side-story' => 'Side story',
      'hors-serie' => 'Hors-série',
      'prologue' => 'Prologue',
      'epilogue' => 'Épilogue',
      'interlude' => 'Interlude',
      _ => word,
    };
    return m == null ? pretty : '$pretty ${m.group(2)}';
  }

  @override
  int compareTo(ChapterKey other) {
    final a = number;
    final b = other.number;
    if (a == null && b == null) {
      if (id.startsWith('volume-') && other.id.startsWith('volume-')) {
        final left = double.tryParse(id.substring(7).replaceAll('-bonus', ''));
        final right = double.tryParse(other.id.substring(7).replaceAll('-bonus', ''));
        if (left != null && right != null && left != right) {
          return left.compareTo(right);
        }
      }
      return id.compareTo(other.id);
    }
    if (a == null) return -1;
    if (b == null) return 1;
    final byNumber = a.compareTo(b);
    // "115.1" and "115.10" share a double value but are distinct chapters.
    return byNumber != 0 ? byNumber : id.compareTo(other.id);
  }

  @override
  bool operator ==(Object other) => other is ChapterKey && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChapterKey($id)';
}
