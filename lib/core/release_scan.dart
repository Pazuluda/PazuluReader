import 'chapter_key.dart';
import 'models.dart';

/// A *work-level* check outcome. A source homepage being up never counts as
/// a checked chapter feed. UI must distinguish checked, skipped and failed.
enum FeedCheckState { checked, failed, unavailable, notConnected, rateLimited }

class FeedCheckResult {
  const FeedCheckResult({
    required this.workId,
    required this.workTitle,
    required this.sourceId,
    required this.sourceName,
    required this.language,
    required this.state,
    required this.checkedAt,
    this.chapterCount = 0,
    this.unreadCount = 0,
    this.unreadKeys = const <String>[],
    this.latestChapter,
    this.nextUnread,
    this.nextUrl,
    this.detail = '',
  });

  final String workId;
  final String workTitle;
  final String sourceId;
  final String sourceName;
  final String language;
  final FeedCheckState state;
  final DateTime checkedAt;
  final int chapterCount;
  final int unreadCount;
  final List<String> unreadKeys;
  final String? latestChapter;
  final String? nextUnread;
  final String? nextUrl;
  final String detail;

  bool get confirmed => state == FeedCheckState.checked;
}

/// Counts what's actually available, separately from the *publication* delta.
/// A library item with no recorded progress is not treated as if its 500
/// historical chapters were newly published. The count is displayed only.
class ReadAvailability {
  const ReadAvailability({
    required this.total,
    required this.unread,
    this.latest,
    this.nextUnread,
    this.nextUrl,
    this.unreadKeys = const <String>[],
  });
  final int total;
  final int unread;
  final String? latest;
  final String? nextUnread;
  final String? nextUrl;
  final List<String> unreadKeys;

  static ReadAvailability calculate(
    ReadingProgress progress,
    Iterable<SourceChapter> chapters,
  ) {
    final unique = <String, SourceChapter>{};
    for (final chapter in chapters) {
      final old = unique[chapter.key.id];
      if (old == null || (old.externalUrl == null && chapter.externalUrl != null)) {
        unique[chapter.key.id] = chapter;
      }
    }
    final sorted = unique.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final previousKey = progress.lastKey == null
        ? null : ChapterKey.parse(progress.lastKey);
    final unread = sorted.where((chapter) {
      if (progress.readKeys.contains(chapter.key.id)) return false;
      // When read history was not recorded for older chapters, chapters below
      // the user's last position must not be reported as unread.
      if (previousKey != null && chapter.key.compareTo(previousKey) < 0) {
        return false;
      }
      return true;
    }).toList();
    return ReadAvailability(
      total: sorted.length,
      unread: unread.length,
      unreadKeys: [for (final c in unread) c.key.id],
      latest: sorted.isEmpty ? null : sorted.last.key.id,
      nextUnread: unread.isEmpty ? null : unread.first.key.id,
      nextUrl: unread.isEmpty ? null : unread.first.externalUrl,
    );
  }
}
