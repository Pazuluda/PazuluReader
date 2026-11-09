import '../models.dart';
import '../source.dart';

/// Ephemeral bridge for pages that an authorized site permits users to read in
/// their own interface. The browser runs inside Pazulu, not another process.
/// The URLs are not persisted; offline CBZ records are persisted separately.
class SessionCaptureSource implements ContentSource {
  final Map<String, List<SourceChapter>> _chapters = {};
  final Map<String, List<PageRef>> _pages = {};

  void add(String workId, SourceChapter chapter, List<String> urls) {
    _chapters.putIfAbsent(workId, () => []).removeWhere((c) => c.chapterId == chapter.chapterId);
    _chapters[workId]!.add(chapter);
    _pages[chapter.chapterId] = [for (final url in urls) PageRef(url)];
  }

  @override String get id => 'session_capture';
  @override String get name => 'Lecteur Pazulu (session)';
  @override String get credit => 'Pages et traductions : site source identifie dans le chapitre.';
  @override List<String> get languages => const ['fr', 'en'];
  @override Map<String, String> get imageHeaders => const {};
  @override Future<List<WorkInfo>> search(String query, {int limit = 30}) async => [];
  @override Future<WorkInfo> getWork(String workId) =>
      Future<WorkInfo>.error(const SourceException('Fiche temporaire indisponible.'));
  @override Future<List<SourceChapter>> listChapters(String workId, {required List<String> langs}) async =>
      (_chapters[workId] ?? const []).where((c) => langs.contains(c.lang)).toList();
  @override Future<List<SourceChapter>> latestChapters(String workId, {required List<String> langs, int limit = 30}) async =>
      (await listChapters(workId, langs: langs)).take(limit).toList();
  @override Future<List<PageRef>> getPages(SourceChapter chapter) async {
    final pages = _pages[chapter.chapterId];
    if (pages == null) throw const SourceException('Pages non conservees. Reouvrir la source ou le CBZ local.');
    return pages;
  }
}
