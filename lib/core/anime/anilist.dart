import 'dart:convert';
import 'dart:isolate';

import '../../engine/http/engine_http.dart';
import '../models.dart';
import '../source.dart';

/// One scheduled (or past) broadcast of an episode, exact time from AniList.
class AnimeAiring {
  const AnimeAiring({required this.mediaId, required this.episode, required this.airingAt});
  final int mediaId;
  final int episode;
  final DateTime airingAt;
}

/// Official streaming link published by AniList (Crunchyroll, ADN, Netflix…).
class StreamingLink {
  const StreamingLink({required this.site, required this.url, this.language});
  final String site;
  final String url;
  final String? language;
}

/// One episode on an official platform (AniList « streamingEpisodes »).
class EpisodeLink {
  const EpisodeLink({required this.number, required this.title, required this.url, required this.site});
  final int number;
  final String title;
  final String url;
  final String site;

  /// « Episode 12 - Titre », « Épisode 3 », « Ep. 4 » → 12, 3, 4.
  static int? numberOf(String title) {
    final m = RegExp(r'(?:episode|épisode|ep\.?)\s*(\d+)', caseSensitive: false).firstMatch(title);
    return m == null ? null : int.tryParse(m[1]!);
  }
}

class AnimeRelation {
  const AnimeRelation({required this.id, required this.title, required this.relation,
    this.status, this.format, this.startDate, this.season, this.seasonYear, this.cover,
    this.type = 'ANIME'});
  final int id;
  final String title;

  /// SEQUEL, PREQUEL, SIDE_STORY, ADAPTATION, SOURCE…
  final String relation;
  final String? status;
  final String? format;
  final DateTime? startDate;
  final String? season;
  final int? seasonYear;
  final String? cover;
  final String type;
}

/// AniList media (anime). Metadata and official links only: Pazulu does not
/// stream video; episodes are watched on the official platforms.
class AnimeInfo {
  const AnimeInfo({
    required this.id,
    required this.title,
    this.altTitles = const [],
    this.description = '',
    this.cover,
    this.banner,
    this.status = 'UNKNOWN',
    this.episodes,
    this.duration,
    this.format,
    this.season,
    this.seasonYear,
    this.startDate,
    this.endDate,
    this.score,
    this.genres = const [],
    this.studios = const [],
    this.nextAiring,
    this.streaming = const [],
    this.episodeLinks = const [],
    this.relations = const [],
    this.trailerYoutube,
    this.siteUrl,
  });

  final int id;
  final String title;
  final List<String> altTitles;
  final String description;
  final String? cover;
  final String? banner;

  /// RELEASING, FINISHED, NOT_YET_RELEASED, CANCELLED, HIATUS
  final String status;
  final int? episodes;
  final int? duration;
  final String? format;
  final String? season;
  final int? seasonYear;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? score;
  final List<String> genres;
  final List<String> studios;
  final AnimeAiring? nextAiring;
  final List<StreamingLink> streaming;
  final List<EpisodeLink> episodeLinks;
  final List<AnimeRelation> relations;
  final String? trailerYoutube;
  final String? siteUrl;

  String get workId => 'anilist:$id';

  /// Episodes already broadcast (from the next airing number when known).
  int? get airedEpisodes {
    final next = nextAiring;
    if (next != null) return next.episode - 1;
    if (status == 'FINISHED') return episodes;
    return null;
  }

  String get statusLabel => switch (status) {
        'RELEASING' => 'En diffusion',
        'FINISHED' => 'Terminé',
        'NOT_YET_RELEASED' => 'À venir',
        'CANCELLED' => 'Annulé',
        'HIATUS' => 'En pause (hiatus)',
        _ => 'Statut inconnu',
      };

  String? get seasonLabel {
    final s = switch (season) {
      'WINTER' => 'Hiver',
      'SPRING' => 'Printemps',
      'SUMMER' => 'Été',
      'FALL' => 'Automne',
      _ => null,
    };
    if (s == null) return seasonYear?.toString();
    return seasonYear == null ? s : '$s $seasonYear';
  }

  List<AnimeRelation> get upcomingSequels => [
        for (final r in relations)
          if (r.relation == 'SEQUEL' && r.type == 'ANIME' &&
              (r.status == 'NOT_YET_RELEASED' || r.status == 'RELEASING'))
            r,
      ];

  WorkInfo toWork() => WorkInfo(
        id: workId,
        title: title,
        altTitles: altTitles,
        description: description,
        coverUrl: cover,
        type: ContentType.anime,
        publicationStatus: statusLabel,
        tags: genres,
        year: seasonYear ?? startDate?.year,
        authors: studios,
        languages: const ['ja'],
        links: [SourceLink(sourceId: AniListClient.sourceId, workId: '$id')],
      );

  static DateTime? _date(Object? raw) {
    if (raw is! Map || raw['year'] is! int) return null;
    return DateTime(raw['year'] as int, raw['month'] is int ? raw['month'] as int : 1,
        raw['day'] is int ? raw['day'] as int : 1);
  }

  static String _clean(String? html) => (html ?? '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&#039;', "'")
      .trim();

  static AnimeInfo? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! int) return null;
    final t = raw['title'] is Map ? raw['title'] as Map : const {};
    final english = t['english'] as String?;
    final romaji = t['romaji'] as String?;
    final native = t['native'] as String?;
    final title = english ?? romaji ?? native ?? 'Sans titre';
    final alts = <String>{
      for (final v in [romaji, english, native]) if (v != null && v != title) v,
      for (final s in (raw['synonyms'] is List ? raw['synonyms'] as List : const []))
        if (s is String) s,
    }.take(12).toList();
    final next = raw['nextAiringEpisode'];
    AnimeAiring? nextAiring;
    if (next is Map && next['episode'] is int && next['airingAt'] is int) {
      nextAiring = AnimeAiring(
        mediaId: raw['id'] as int,
        episode: next['episode'] as int,
        airingAt: DateTime.fromMillisecondsSinceEpoch((next['airingAt'] as int) * 1000),
      );
    }
    final streaming = <StreamingLink>[];
    for (final l in (raw['externalLinks'] is List ? raw['externalLinks'] as List : const [])) {
      if (l is! Map || l['type'] != 'STREAMING' || l['url'] is! String) continue;
      final uri = Uri.tryParse(l['url'] as String);
      if (uri == null || uri.scheme != 'https') continue;
      streaming.add(StreamingLink(site: '${l['site'] ?? uri.host}', url: uri.toString(),
          language: l['language'] as String?));
    }
    final episodeLinks = <EpisodeLink>[];
    for (final e in (raw['streamingEpisodes'] is List ? raw['streamingEpisodes'] as List : const [])) {
      if (e is! Map || e['url'] is! String) continue;
      final uri = Uri.tryParse(e['url'] as String);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final title = '${e['title'] ?? ''}';
      final n = EpisodeLink.numberOf(title);
      if (n == null) continue;
      episodeLinks.add(EpisodeLink(number: n, title: title, url: uri.toString(),
          site: '${e['site'] ?? uri.host}'));
    }
    final relations = <AnimeRelation>[];
    final edges = raw['relations'] is Map ? (raw['relations'] as Map)['edges'] : null;
    for (final e in (edges is List ? edges : const [])) {
      if (e is! Map || e['node'] is! Map) continue;
      final n = e['node'] as Map;
      if (n['id'] is! int) continue;
      final nt = n['title'] is Map ? n['title'] as Map : const {};
      relations.add(AnimeRelation(
        id: n['id'] as int,
        title: (nt['english'] ?? nt['romaji'] ?? nt['native'] ?? '?') as String,
        relation: '${e['relationType'] ?? ''}',
        status: n['status'] as String?,
        format: n['format'] as String?,
        type: '${n['type'] ?? 'ANIME'}',
        startDate: _date(n['startDate']),
        season: n['season'] as String?,
        seasonYear: n['seasonYear'] as int?,
        cover: n['coverImage'] is Map ? (n['coverImage'] as Map)['large'] as String? : null,
      ));
    }
    final studios = <String>[];
    final studioNodes = raw['studios'] is Map ? (raw['studios'] as Map)['nodes'] : null;
    for (final s in (studioNodes is List ? studioNodes : const [])) {
      if (s is Map && s['name'] is String) studios.add(s['name'] as String);
    }
    final trailer = raw['trailer'];
    final cover = raw['coverImage'] is Map ? raw['coverImage'] as Map : const {};
    return AnimeInfo(
      id: raw['id'] as int,
      title: title,
      altTitles: alts,
      description: _clean(raw['description'] as String?),
      cover: (cover['extraLarge'] ?? cover['large']) as String?,
      banner: raw['bannerImage'] as String?,
      status: '${raw['status'] ?? 'UNKNOWN'}',
      episodes: raw['episodes'] as int?,
      duration: raw['duration'] as int?,
      format: raw['format'] as String?,
      season: raw['season'] as String?,
      seasonYear: raw['seasonYear'] as int?,
      startDate: _date(raw['startDate']),
      endDate: _date(raw['endDate']),
      score: raw['averageScore'] as int?,
      genres: [for (final g in (raw['genres'] is List ? raw['genres'] as List : const [])) if (g is String) g],
      studios: studios,
      nextAiring: nextAiring,
      streaming: streaming,
      episodeLinks: episodeLinks,
      relations: relations,
      trailerYoutube: trailer is Map && trailer['site'] == 'youtube' && trailer['id'] is String
          ? trailer['id'] as String : null,
      siteUrl: raw['siteUrl'] as String?,
    );
  }
}

/// Client for the public AniList GraphQL API (https://graphql.anilist.co).
/// Rate limit (90 requests/min) handled by the engine: 429 + Retry-After.
class AniListClient {
  AniListClient(this.http) {
    http.configureHost('graphql.anilist.co', maxConcurrent: 2, requestsPerMinute: 60);
  }

  static const sourceId = 'anilist';
  static final Uri endpoint = Uri.parse('https://graphql.anilist.co');
  final EngineHttpClient http;

  static const _fields = '''
    id title { romaji english native } synonyms description(asHtml: false)
    coverImage { extraLarge large } bannerImage status(version: 2) episodes duration format
    season seasonYear averageScore genres siteUrl
    startDate { year month day } endDate { year month day }
    nextAiringEpisode { episode airingAt }
    studios(isMain: true) { nodes { name } }
    externalLinks { site url type language }
    streamingEpisodes { title url site }
    trailer { id site }
    relations { edges { relationType node { id type status(version: 2) format season seasonYear
      title { romaji english native } startDate { year month day } coverImage { large } } } }
  ''';

  static const _light = '''
    id title { romaji english native } synonyms coverImage { extraLarge large }
    status(version: 2) episodes format season seasonYear averageScore genres
    startDate { year month day } nextAiringEpisode { episode airingAt }
  ''';

  Future<Map<String, dynamic>> _query(String query, Map<String, dynamic> variables,
      {bool cache = true}) async {
    final response = await http.get(endpoint,
        method: 'POST',
        allowedHosts: const ['graphql.anilist.co'],
        cache: cache,
        sourceId: sourceId,
        timeout: const Duration(seconds: 15),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}));
    final text = response.text;
    // Big answers (planning with episode links) are decoded off the UI
    // thread: no stutter while scrolling.
    final decoded = text.length > 64 * 1024 ? await Isolate.run(() => jsonDecode(text)) : jsonDecode(text);
    if (decoded is! Map) throw const SourceException('Réponse AniList illisible.');
    final errors = decoded['errors'];
    if (!response.ok || errors is List && errors.isNotEmpty) {
      final message = errors is List && errors.isNotEmpty && errors.first is Map
          ? '${(errors.first as Map)['message']}' : 'HTTP ${response.status}';
      throw SourceException('AniList : $message', statusCode: response.status);
    }
    final data = decoded['data'];
    if (data is! Map) throw const SourceException('AniList : aucune donnée.');
    return data.cast<String, dynamic>();
  }

  List<AnimeInfo> _media(Map<String, dynamic> data) {
    final page = data['Page'];
    final list = page is Map ? page['media'] : null;
    return [
      for (final m in (list is List ? list : const []))
        if (AnimeInfo.fromJson(m) case final AnimeInfo a) a,
    ];
  }

  Future<List<AnimeInfo>> search(String query, {int perPage = 30}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final data = await _query('query (\$q: String, \$n: Int) { Page(perPage: \$n) { '
        'media(search: \$q, type: ANIME, sort: SEARCH_MATCH, isAdult: false) { $_light } } }',
        {'q': q, 'n': perPage});
    return _media(data);
  }

  /// Popular anime of the current season, then all-time trending.
  Future<List<AnimeInfo>> trending({int perPage = 40}) async {
    final data = await _query('query (\$n: Int) { Page(perPage: \$n) { '
        'media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { $_light } } }',
        {'n': perPage});
    return _media(data);
  }

  Future<AnimeInfo> details(int id) async {
    final data = await _query('query (\$id: Int) { Media(id: \$id, type: ANIME) { $_fields } }',
        {'id': id});
    final media = AnimeInfo.fromJson(data['Media']);
    if (media == null) throw const SourceException('Animé introuvable sur AniList.');
    return media;
  }

  /// Full data for many anime at once (library planning), 50 per request.
  Future<List<AnimeInfo>> batch(List<int> ids) async {
    final out = <AnimeInfo>[];
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.skip(i).take(50).toList();
      final data = await _query('query (\$ids: [Int]) { Page(perPage: 50) { '
          'media(id_in: \$ids, type: ANIME) { $_fields } } }', {'ids': chunk}, cache: false);
      out.addAll(_media(data));
    }
    return out;
  }

  /// Exact broadcast times between [from] and [to] for [ids].
  Future<List<AnimeAiring>> schedule(List<int> ids, DateTime from, DateTime to) async {
    if (ids.isEmpty) return const [];
    final out = <AnimeAiring>[];
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.skip(i).take(50).toList();
      final data = await _query(
          'query (\$ids: [Int], \$a: Int, \$b: Int) { Page(perPage: 100) { '
          'airingSchedules(mediaId_in: \$ids, airingAt_greater: \$a, airingAt_lesser: \$b, '
          'sort: TIME) { mediaId episode airingAt } } }',
          {
            'ids': chunk,
            'a': from.millisecondsSinceEpoch ~/ 1000,
            'b': to.millisecondsSinceEpoch ~/ 1000,
          },
          cache: false);
      final page = data['Page'];
      final list = page is Map ? page['airingSchedules'] : null;
      for (final s in (list is List ? list : const [])) {
        if (s is Map && s['mediaId'] is int && s['episode'] is int && s['airingAt'] is int) {
          out.add(AnimeAiring(
            mediaId: s['mediaId'] as int,
            episode: s['episode'] as int,
            airingAt: DateTime.fromMillisecondsSinceEpoch((s['airingAt'] as int) * 1000),
          ));
        }
      }
    }
    out.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return out;
  }

  /// Every anime broadcast (all series) between [from] and [to], with the
  /// series record and its official streaming links. Adult titles excluded.
  Future<List<(AnimeAiring, AnimeInfo)>> airingBetween(DateTime from, DateTime to,
      {int maxPages = 12}) async {
    final out = <(AnimeAiring, AnimeInfo)>[];
    for (var page = 1; page <= maxPages; page++) {
      final data = await _query(
          'query (\$p: Int, \$a: Int, \$b: Int) { Page(page: \$p, perPage: 50) { '
          'pageInfo { hasNextPage } '
          'airingSchedules(airingAt_greater: \$a, airingAt_lesser: \$b, sort: TIME) { '
          'episode airingAt media { $_light isAdult countryOfOrigin bannerImage '
          'externalLinks { site url type language } streamingEpisodes { title url site } } } } }',
          {
            'p': page,
            'a': from.millisecondsSinceEpoch ~/ 1000,
            'b': to.millisecondsSinceEpoch ~/ 1000,
          });
      final pageData = data['Page'];
      final list = pageData is Map ? pageData['airingSchedules'] : null;
      for (final s in (list is List ? list : const [])) {
        if (s is! Map || s['episode'] is! int || s['airingAt'] is! int) continue;
        final media = s['media'];
        if (media is! Map || media['isAdult'] == true) continue;
        final info = AnimeInfo.fromJson(media);
        if (info == null) continue;
        out.add((
          AnimeAiring(mediaId: info.id, episode: s['episode'] as int,
              airingAt: DateTime.fromMillisecondsSinceEpoch((s['airingAt'] as int) * 1000)),
          info,
        ));
      }
      final more = pageData is Map && pageData['pageInfo'] is Map &&
          (pageData['pageInfo'] as Map)['hasNextPage'] == true;
      if (!more) break;
    }
    return out;
  }

  /// Comics catalogue with rich metadata (genres, score, status, number of
  /// chapters) for « Découvrir ». [country]: JP manga, KR manhwa, CN manhua.
  Future<List<WorkInfo>> comicCatalog({
    String sort = 'TRENDING_DESC',
    String? genre,
    String? country,
    String? search,
    String? status,
    int page = 1,
    int perPage = 40,
  }) async {
    final args = <String>[
      if (status != null) r'status: $status',
      'type: MANGA', 'isAdult: false', r'sort: [$sort]', 'format_not: NOVEL',
      if (genre != null) r'genre: $genre',
      if (country != null) r'countryOfOrigin: $country',
      if (search != null) r'search: $search',
    ];
    // GraphQL refuses declared-but-unused variables: declare only those used.
    final decls = <String>[
      r'$p: Int', r'$n: Int', r'$sort: MediaSort',
      if (genre != null) r'$genre: String',
      if (country != null) r'$country: CountryCode',
      if (search != null) r'$search: String',
      if (status != null) r'$status: MediaStatus',
    ];
    final data = await _query(
        'query (${decls.join(', ')}) { Page(page: \$p, perPage: \$n) { media('
        '${args.join(', ')}) { id title { romaji english native } synonyms '
        'coverImage { extraLarge large } status(version: 2) chapters volumes format countryOfOrigin '
        'averageScore popularity genres startDate { year } description(asHtml: false) '
        'staff(perPage: 2, sort: RELEVANCE) { nodes { name { full } } } } } }',
        {
          'p': page,
          'n': perPage,
          'sort': sort,
          if (genre != null) 'genre': genre,
          if (country != null) 'country': country,
          if (search != null) 'search': search,
          if (status != null) 'status': status,
        });
    final pageData = data['Page'];
    final list = pageData is Map ? pageData['media'] : null;
    return [
      for (final m in (list is List ? list : const []))
        if (comicFromJson(m) case final WorkInfo w) w,
    ];
  }

  static WorkInfo? comicFromJson(Object? m) {
    if (m is! Map || m['id'] is! int) return null;
    final t = m['title'] is Map ? m['title'] as Map : const {};
    final english = t['english'] as String?;
    final romaji = t['romaji'] as String?;
    final title = english ?? romaji ?? t['native'] as String?;
    if (title == null) return null;
    final cover = m['coverImage'] is Map ? m['coverImage'] as Map : const {};
    final type = switch (m['countryOfOrigin']) {
      'KR' => ContentType.manhwa,
      'CN' || 'TW' || 'HK' => ContentType.manhua,
      _ => ContentType.manga,
    };
    final status = switch (m['status']) {
      'RELEASING' => 'En cours',
      'FINISHED' => 'Terminé',
      'HIATUS' => 'En pause',
      'CANCELLED' => 'Annulé',
      'NOT_YET_RELEASED' => 'À paraître',
      _ => null,
    };
    final staff = m['staff'] is Map ? (m['staff'] as Map)['nodes'] : null;
    final score = m['averageScore'];
    return WorkInfo(
      id: 'anilist-manga:${m['id']}',
      title: title,
      altTitles: {
        for (final v in [romaji, english, t['native']]) if (v is String && v != title) v,
        for (final s in (m['synonyms'] is List ? m['synonyms'] as List : const [])) if (s is String) s,
      }.take(12).toList(),
      description: AnimeInfo._clean(m['description'] as String?),
      coverUrl: (cover['extraLarge'] ?? cover['large']) as String?,
      type: type,
      publicationStatus: status,
      tags: [
        if (score is int) '★ $score%',
        for (final g in (m['genres'] is List ? m['genres'] as List : const [])) if (g is String) g,
      ],
      year: m['startDate'] is Map ? (m['startDate'] as Map)['year'] as int? : null,
      authors: [
        for (final n in (staff is List ? staff : const []))
          if (n is Map && n['name'] is Map && (n['name'] as Map)['full'] is String)
            (n['name'] as Map)['full'] as String,
      ],
      lastChapter: m['chapters'] is int ? '${m['chapters']}' : null,
      links: const [],
    );
  }

  static int? idOf(WorkInfo work) {
    for (final l in work.links) {
      if (l.sourceId == sourceId) return int.tryParse(l.workId);
    }
    if (work.id.startsWith('anilist:')) return int.tryParse(work.id.substring(8));
    return null;
  }
}
