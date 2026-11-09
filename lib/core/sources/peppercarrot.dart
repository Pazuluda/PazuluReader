import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chapter_key.dart';
import '../models.dart';
import '../source.dart';

/// Connector for a documented, openly published webcomic.
/// Only metadata is loaded for chapter listings; image URLs are generated
/// exclusively by getPages, which is invoked when the user starts reading.
/// Documentation: https://www.peppercarrot.com/go/documentation/130_API.html
class PepperCarrotSource implements ContentSource {
  PepperCarrotSource({http.Client? client}) : _client = client ?? http.Client();

  static const String site = 'https://www.peppercarrot.com';
  static const String imageRoot = 'https://peppercarrot.com/0_sources';
  static const String indexUrl = '$imageRoot/episodes.json';
  static const String workId = 'peppercarrot';

  final http.Client _client;
  List<_Episode>? _index;
  DateTime? _indexLoadedAt;

  @override String get id => 'peppercarrot';
  @override String get name => 'Pepper&Carrot';
  @override List<String> get languages => const ['fr', 'en'];
  @override Map<String, String> get imageHeaders => const {};
  @override String get credit =>
      'Pepper&Carrot par David Revoy. Traductions : equipes creditees par l auteur. '
      'Consulter les conditions de licence du site.';

  static WorkInfo get _work => const WorkInfo(
        id: 'peppercarrot:peppercarrot',
        title: 'Pepper&Carrot',
        altTitles: ['Pepper et Carrot', 'Poivre et Carotte'],
        description: 'Une bande dessinee libre de David Revoy, '
            'dans l univers magique d Hereva.',
        coverUrl: '$imageRoot/ep01_Potion-of-Flight/low-res/'
            'en_Pepper-and-Carrot_by-David-Revoy_E01.jpg',
        type: ContentType.webtoon,
        authors: ['David Revoy'],
        languages: ['fr', 'en'],
        longStrip: false,
        links: [SourceLink(sourceId: 'peppercarrot', workId: 'peppercarrot')],
      );

  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async {
    final term = query.trim().toLowerCase();
    // No HTTP request at all for search/summary: never fetch images or chapters.
    if (term.isNotEmpty && !const [
      'pepper', 'carrot', 'poivre', 'carotte', 'pipro', 'karo',
    ].any(term.contains)) {
      return [];
    }
    return [_work];
  }

  @override
  Future<WorkInfo> getWork(String requestedId) async {
    if (requestedId != workId) {
      throw const SourceException('Oeuvre Pepper&Carrot introuvable.');
    }
    return _work;
  }

  Future<List<_Episode>> _episodes() async {
    final loadedAt = _indexLoadedAt;
    if (_index != null && loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 30)) {
      return _index!;
    }
    late final http.Response response;
    try {
      response = await _client.get(Uri.parse(indexUrl)).timeout(
          const Duration(seconds: 15));
    } catch (e) {
      throw SourceException('Catalogue Pepper&Carrot indisponible : $e');
    }
    if (response.statusCode != 200) {
      throw SourceException('Pepper&Carrot : HTTP ${response.statusCode}',
          statusCode: response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const SourceException('Index Pepper&Carrot inattendu.');
    }
    final episodes = <_Episode>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name'];
      final count = item['total_pages'];
      final languages = item['translated_languages'];
      if (name is! String || count is! int || languages is! List ||
          !RegExp(r'^ep\d{2}_[a-zA-Z0-9_-]+$').hasMatch(name) ||
          count < 1 || count > 300) continue;
      final langs = languages.whereType<String>()
          .where((value) => value == 'fr' || value == 'en').toSet();
      if (langs.isEmpty) continue;
      episodes.add(_Episode(name, count, langs));
    }
    if (episodes.isEmpty) {
      throw const SourceException('Aucun episode lisible trouve dans le catalogue.');
    }
    _index = episodes;
    _indexLoadedAt = DateTime.now();
    return episodes;
  }

  @override
  Future<List<SourceChapter>> listChapters(
    String requestedId, {
    required List<String> langs,
  }) async {
    if (requestedId != workId) return [];
    final episodes = await _episodes();
    return [
      for (final episode in episodes)
        for (final lang in langs.toSet())
          if (episode.langs.contains(lang))
            SourceChapter(
              sourceId: id,
              chapterId: '${episode.name}:$lang',
              key: ChapterKey.parse(episode.number.toString()),
              lang: lang,
              group: 'Pepper&Carrot · David Revoy',
              title: episode.title,
              pages: episode.totalPages + 1,
            ),
    ];
  }

  @override
  Future<List<SourceChapter>> latestChapters(
    String requestedId, {
    required List<String> langs,
    int limit = 30,
  }) async {
    final all = await listChapters(requestedId, langs: langs);
    all.sort((a, b) => b.key.compareTo(a.key));
    return all.take(limit).toList();
  }

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async {
    if (chapter.sourceId != id) {
      throw const SourceException('Chapitre et source incompatibles.');
    }
    final match = RegExp(r'^(ep(\d{2})_[a-zA-Z0-9_-]+):(fr|en)$')
        .firstMatch(chapter.chapterId);
    if (match == null) {
      throw const SourceException('Identifiant de chapitre invalide.');
    }
    final episode = match.group(1)!;
    final number = match.group(2)!;
    final lang = match.group(3)!;
    final count = chapter.pages;
    if (count < 1 || count > 301) {
      throw const SourceException('Nombre de pages invalide.');
    }
    return [
      for (var page = 0; page < count; page++)
        PageRef('$imageRoot/$episode/low-res/'
            '${lang}_Pepper-and-Carrot_by-David-Revoy_E$number'
            'P${page.toString().padLeft(2, '0')}.jpg'),
    ];
  }
}

class _Episode {
  const _Episode(this.name, this.totalPages, this.langs);
  final String name;
  final int totalPages;
  final Set<String> langs;

  int get number => int.parse(name.substring(2, 4));
  String get title => name.substring(name.indexOf('_') + 1).replaceAll('-', ' ');
}
