import 'models.dart';

/// Un « moment » marqué dans le lecteur : une page précise d'un chapitre
/// (une scène préférée), à retrouver dans « Mes moments ».
class Moment {
  Moment({
    required this.work,
    required this.chapterId,
    required this.chapterLabel,
    required this.page,
    required this.at,
    this.note = '',
  });

  final WorkInfo work;
  final String chapterId;
  final String chapterLabel;
  final int page;
  final DateTime at;
  String note;

  String get key => '${work.id}|$chapterId|$page';

  Map<String, dynamic> toJson() => {
        'work': work.toJson(),
        'chapterId': chapterId,
        'chapterLabel': chapterLabel,
        'page': page,
        'at': at.toIso8601String(),
        if (note.isNotEmpty) 'note': note,
      };

  static Moment? fromJson(Object? raw) {
    if (raw is! Map || raw['work'] is! Map || raw['chapterId'] is! String) return null;
    try {
      return Moment(
        work: WorkInfo.fromJson(Map<String, dynamic>.from(raw['work'] as Map)),
        chapterId: raw['chapterId'] as String,
        chapterLabel: '${raw['chapterLabel'] ?? raw['chapterId']}',
        page: (raw['page'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse('${raw['at']}') ?? DateTime.now(),
        note: '${raw['note'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}
