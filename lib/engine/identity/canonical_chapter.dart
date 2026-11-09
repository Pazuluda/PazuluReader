import '../../core/chapter_key.dart';
import '../../core/models.dart';

enum ChapterKind { regular, extra, volumeBonus, volume, special, oneshot }

/// How confident the engine is that two source chapters are the same text.
enum Equivalence {
  /// Same kind, same exact number, compatible edition: automatic fallback OK.
  exact,

  /// Same number but some identity data is missing or differs mildly
  /// (unknown volume of an extra, different edition label…). Ask the user.
  needsConfirmation,

  /// Different chapter: never substitute.
  different,
}

/// Canonical identity of a chapter: content type / edition, volume, exact
/// number with its decimal suffix, extras and bonus, language and group.
///
/// `115.1` and `115.2` are different chapters; `Extra 1` is not chapter 1;
/// chapter 140 of a novel is not chapter 140 of its manga adaptation.
class CanonicalChapter {
  const CanonicalChapter({
    required this.kind,
    required this.keyId,
    this.number,
    this.volume,
    this.edition,
    this.lang,
    this.group,
    this.title,
  });

  final ChapterKind kind;

  /// [ChapterKey.id] — written decimals preserved.
  final String keyId;
  final String? number;
  final String? volume;

  /// manga / novel / webnovel / anime / colored / official… when known.
  final String? edition;
  final String? lang;
  final String? group;
  final String? title;

  factory CanonicalChapter.of(SourceChapter chapter, {String? edition}) {
    final key = chapter.key;
    final id = key.id;
    final ChapterKind kind;
    String? number;
    if (key.number != null) {
      kind = ChapterKind.regular;
      number = id;
    } else if (id.startsWith('volume-') && id.endsWith('-bonus')) {
      kind = ChapterKind.volumeBonus;
    } else if (id.startsWith('volume-')) {
      kind = ChapterKind.volume;
    } else if (id == 'oneshot') {
      kind = ChapterKind.oneshot;
    } else if (RegExp(r'^(?:extra|bonus|omake|side-story|hors-serie)(?:-|$)').hasMatch(id)) {
      kind = ChapterKind.extra;
      final m = RegExp(r'-(\d+(?:\.\d+)?)$').firstMatch(id);
      number = m?.group(1);
    } else {
      kind = ChapterKind.special;
    }
    String? volume = chapter.volume?.trim();
    if (volume != null && volume.isEmpty) volume = null;
    if (volume == null && id.startsWith('volume-')) {
      volume = id.substring(7).replaceAll('-bonus', '');
    }
    return CanonicalChapter(
      kind: kind,
      keyId: id,
      number: number,
      volume: volume == null ? null : _normVolume(volume),
      edition: edition?.toLowerCase(),
      lang: chapter.lang,
      group: chapter.group,
      title: chapter.title,
    );
  }

  static String _normVolume(String raw) {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(raw);
    if (m == null) return raw.toLowerCase();
    return ChapterKey.parse(m.group(1)).id;
  }

  /// Stable identity used for routing; language and group excluded on
  /// purpose: they distinguish *readers*, not *chapters*.
  String get identity {
    final ed = edition == null ? '' : '$edition:';
    return switch (kind) {
      ChapterKind.regular => '${ed}ch:$keyId',
      ChapterKind.extra => '${ed}extra:${volume ?? '?'}:$keyId',
      ChapterKind.volumeBonus => '${ed}volbonus:$keyId',
      ChapterKind.volume => '${ed}vol:$keyId',
      ChapterKind.oneshot => '${ed}oneshot',
      ChapterKind.special => '${ed}special:$keyId',
    };
  }

  static const _comicEditions = {'manga', 'manhwa', 'manhua', 'webtoon', 'comic'};

  /// Decides whether [other] may replace this chapter automatically.
  Equivalence compare(CanonicalChapter other) {
    if (kind != other.kind || keyId != other.keyId) return Equivalence.different;
    final a = edition;
    final b = other.edition;
    if (a != null && b != null && a != b) {
      final bothComics = _comicEditions.contains(a) && _comicEditions.contains(b);
      // A manhwa listed as "webtoon" elsewhere is the same comic; a novel
      // and its manga adaptation never are.
      if (!bothComics) return Equivalence.different;
    }
    final volumesKnown = volume != null && other.volume != null;
    return switch (kind) {
      // Chapter numbers are global inside a work; a different explicit
      // volume for the same number signals a renumbered edition.
      ChapterKind.regular => volumesKnown && volume != other.volume
          ? Equivalence.needsConfirmation
          : Equivalence.exact,
      // "Extra 1" exists in several volumes of many series.
      ChapterKind.extra => !volumesKnown
          ? Equivalence.needsConfirmation
          : (volume == other.volume ? Equivalence.exact : Equivalence.different),
      ChapterKind.special => Equivalence.needsConfirmation,
      ChapterKind.volume || ChapterKind.volumeBonus || ChapterKind.oneshot =>
          Equivalence.exact,
    };
  }

  @override
  String toString() => 'CanonicalChapter($identity, $lang, $group)';
}

/// Edition label of a work, used to keep novel / manga / anime apart.
String editionOf(WorkInfo? work) => switch (work?.type) {
      ContentType.novel => 'novel',
      ContentType.anime => 'anime',
      ContentType.manga => 'manga',
      ContentType.manhwa => 'manhwa',
      ContentType.manhua => 'manhua',
      ContentType.webtoon => 'webtoon',
      _ => 'comic',
    };

/// Reads a chapter label as published in a list ("Solo Leveling Chapitre
/// 115.1", "Vol.3 Ch.21", "Chapitre Extra 1", "Volume 12 - Bonus").
///
/// Explicit markers win over stray numbers: "Kaiju No. 8 Chapter 100" is
/// chapter 100, not 8. Without any marker the LAST number is used, because
/// titles often start with a number belonging to the series name.
class ChapterLabelParser {
  const ChapterLabelParser._();

  static final RegExp _marker = RegExp(
      r'(?<![a-z])(?:chapitre|chapter|chap\.?|ch\.?|[eé]pisode|[eé]p\.?)\s*[:#.-]?\s*'
      r'(?=(?:extra|bonus|special|omake|side|hors|prologue|[eé]pilogue|\d))',
      caseSensitive: false);
  static final RegExp _special = RegExp(
      r'(?<![a-z])(?:extra|bonus|special|omake|side[\s_-]*story|hors[\s_-]*s[eé]rie|'
      r'prologue|[eé]pilogue|interlude)(?![a-z])',
      caseSensitive: false);
  static final RegExp _volume = RegExp(
      r'(?<![a-z])(?:volume|vol\.?|tome)\s*[:#.-]?\s*(\d+(?:[.,]\d+)?)',
      caseSensitive: false);
  static final RegExp _numbers = RegExp(r'\d+(?:[.,]\d+)?');

  static (ChapterKey, String?) parse(String label) {
    final text = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    final volumeMatch = _volume.firstMatch(text);
    final volume = volumeMatch?.group(1)?.replaceAll(',', '.');
    final marker = _marker.firstMatch(text);
    if (marker != null) {
      return (ChapterKey.parse(text.substring(marker.start)), volume);
    }
    final special = _special.firstMatch(text);
    if (special != null) {
      // "Volume 12 - Bonus" keeps its volume context.
      if (volumeMatch != null && volumeMatch.start < special.start) {
        return (ChapterKey.parse(text.substring(volumeMatch.start)), volume);
      }
      return (ChapterKey.parse(text.substring(special.start)), volume);
    }
    if (volumeMatch != null) {
      final after = text.substring(volumeMatch.end);
      final rest = _numbers.firstMatch(after);
      if (rest == null) return (ChapterKey.parse(text.substring(volumeMatch.start)), volume);
      return (ChapterKey.parse(rest.group(0)), volume);
    }
    final all = _numbers.allMatches(text).toList();
    if (all.isEmpty) return (ChapterKey.parse(text), null);
    return (ChapterKey.parse(all.last.group(0)), null);
  }
}
