import 'chapter_key.dart';

/// Only explicit chapter markers are trusted. A year, volume or a number in
/// a series title must never silently become a chapter number.
class ChapterIdentity {
  static final RegExp _marked = RegExp(
    r'(?:^|[^a-z])(?:chapitre|chapter|chap|ch|episode|ep)[\s.:#_/-]*(\d{1,6}(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _numericFile = RegExp(r'^(\d{1,6}(?:[.,]\d{1,2})?)\.(?:cbz|zip)$',
      caseSensitive: false);

  static ChapterKey? detect({required String title, String? url}) {
    final found = _marked.firstMatch(title) ??
        (url == null ? null : _marked.firstMatch(Uri.tryParse(url)?.path ?? url));
    if (found != null) return ChapterKey.parse(found.group(1));
    final name = title.split(RegExp(r'[\\/]')).last.trim();
    final numeric = _numericFile.firstMatch(name);
    return numeric == null ? null : ChapterKey.parse(numeric.group(1));
  }
}
