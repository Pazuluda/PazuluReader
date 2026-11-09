import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../engine/availability.dart';
import '../../engine/routing/circuit_breaker.dart' show parseRetryAfter;
import '../chapter_key.dart';
import '../models.dart';
import '../source.dart';

/// Connecteur MangaDex (API publique officielle).
///
/// Règles d'utilisation MangaDex respectées : crédit à MangaDex et aux
/// groupes de traduction, aucune publicité, aucun service payant,
/// requêtes limitées (≈ 4 par seconde).
class MangaDexSource implements ContentSource {
  MangaDexSource({http.Client? client, List<String>? contentRatings})
      : _client = client ?? http.Client(),
        contentRatings = contentRatings ?? const ['safe', 'suggestive'];

  static const String apiBase = 'https://api.mangadex.org';
  static const String uploadsBase = 'https://uploads.mangadex.org';
  static const String userAgent = 'PazuluReader/2.0 (application personnelle)';

  final http.Client _client;

  /// Classements de contenu autorisés ("safe", "suggestive", ...).
  List<String> contentRatings;

  @override
  String get id => 'mangadex';

  @override
  String get name => 'MangaDex';

  @override
  List<String> get languages => const ['en', 'fr'];

  @override
  String get credit =>
      'Données et images : MangaDex. Traductions : groupes indiqués sur chaque chapitre.';

  @override
  Map<String, String> get imageHeaders => const {'User-Agent': userAgent};

  // -------------------------------------------------------------------------
  // Limitation du débit : une requête toutes les 250 ms maximum.
  // -------------------------------------------------------------------------

  Future<void> _gate = Future<void>.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _throttle() {
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    return previous.then((_) async {
      final wait =
          _last.add(const Duration(milliseconds: 250)).difference(DateTime.now());
      if (!wait.isNegative) await Future<void>.delayed(wait);
      _last = DateTime.now();
      done.complete();
    });
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, dynamic>? params,
  ]) async {
    final uri = Uri.parse('$apiBase$path').replace(queryParameters: params);
    late http.Response res;
    // « Connection closed before full header », time-outs and 502/503/504
    // are frequent and short: two more attempts before giving up.
    for (var attempt = 0;; attempt++) {
      await _throttle();
      try {
        res = await _client
            .get(uri, headers: const {'User-Agent': userAgent})
            .timeout(const Duration(seconds: 20));
        if (res.statusCode >= 502 && res.statusCode <= 504 && attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
          continue;
        }
        break;
      } on TimeoutException {
        if (attempt < 2) continue;
        throw const SourceException('MangaDex ne répond pas (délai dépassé).');
      } catch (e) {
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          continue;
        }
        throw const SourceException('Connexion à MangaDex impossible (connexion '
            'interrompue). Les autres sources prennent le relais.');
      }
    }
    if (res.statusCode == 429) {
      // Respect Retry-After; never hammer the API to force access.
      final wait = parseRetryAfter(res.headers['retry-after']) ??
          const Duration(seconds: 30);
      // Later calls wait (bounded) instead of failing again immediately.
      _last = DateTime.now().add(
          wait > const Duration(minutes: 2) ? const Duration(minutes: 2) : wait);
      throw ChapterRestrictedException(
        'MangaDex limite les requêtes (HTTP 429). Nouvel essai possible dans '
        '${wait.inSeconds} s.',
        kind: AccessKind.rateLimited,
        statusCode: 429,
        retryAfter: wait,
      );
    }
    if (res.statusCode != 200) {
      throw SourceException(
        'MangaDex a répondu ${res.statusCode}.',
        statusCode: res.statusCode,
      );
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map) {
      throw const SourceException('Réponse MangaDex inattendue.');
    }
    return body.cast<String, dynamic>();
  }

  // -------------------------------------------------------------------------
  // Recherche et fiches
  // -------------------------------------------------------------------------

  @override
  Future<List<WorkInfo>> search(String query, {int limit = 30}) async {
    final params = <String, dynamic>{
      'limit': '$limit',
      'includes[]': const ['cover_art', 'author', 'artist'],
      'contentRating[]': contentRatings,
    };
    final q = query.trim();
    if (q.isEmpty) {
      params['order[followedCount]'] = 'desc';
    } else {
      params['title'] = q;
      params['order[relevance]'] = 'desc';
    }
    final json = await _get('/manga', params);
    final data = (json['data'] as List? ?? const []);
    return [
      for (final d in data)
        if (d is Map) parseManga(d.cast<String, dynamic>()),
    ];
  }

  @override
  Future<WorkInfo> getWork(String workId) async {
    final json = await _get('/manga/$workId', {
      'includes[]': const ['cover_art', 'author', 'artist'],
    });
    final data = json['data'];
    if (data is! Map) throw const SourceException('Œuvre introuvable.');
    return parseManga(data.cast<String, dynamic>());
  }

  // -------------------------------------------------------------------------
  // Chapitres
  // -------------------------------------------------------------------------

  @override
  Future<List<SourceChapter>> listChapters(
    String workId, {
    required List<String> langs,
  }) async {
    final out = <SourceChapter>[];
    const limit = 500;
    var offset = 0;
    while (true) {
      final json = await _get('/manga/$workId/feed', {
        'limit': '$limit',
        'offset': '$offset',
        'translatedLanguage[]': langs,
        'order[chapter]': 'asc',
        'includes[]': const ['scanlation_group'],
        'contentRating[]': const ['safe', 'suggestive', 'erotica', 'pornographic'],
      });
      final data = (json['data'] as List? ?? const []);
      for (final d in data) {
        if (d is! Map) continue;
        final c = parseChapter(d.cast<String, dynamic>());
        if (c != null) out.add(c);
      }
      final total = (json['total'] as int?) ?? 0;
      offset += limit;
      // L'API refuse offset + limit > 10 000.
      if (data.isEmpty || offset >= total || offset + limit > 10000) break;
    }
    return out;
  }

  @override
  Future<List<SourceChapter>> latestChapters(
    String workId, {
    required List<String> langs,
    int limit = 30,
  }) async {
    final out = <SourceChapter>[];
    // Flux indépendants par langue : 40 sorties EN ne doivent plus évincer
    // toutes les sorties FR de la fenêtre de vérification.
    for (final lang in langs.toSet()) {
      final json = await _get('/chapter', {
        'manga': workId,
        'limit': '${limit.clamp(1, 100)}',
        'translatedLanguage[]': [lang],
        'order[readableAt]': 'desc',
        'includes[]': const ['scanlation_group'],
        'contentRating[]': contentRatings,
      });
      final data = (json['data'] as List? ?? const []);
      for (final d in data) {
        if (d is! Map) continue;
        final c = parseChapter(d.cast<String, dynamic>());
        if (c != null) out.add(c);
      }
    }
    return out;
  }

  /// Every chapter published in [lang] since [since] (all series), newest
  /// first, with its series id. Used by the weekly release planning.
  Future<List<(String mangaId, SourceChapter chapter)>> recentChapters({
    required String lang,
    required DateTime since,
    int maxPages = 12,
  }) async {
    final out = <(String, SourceChapter)>[];
    final stamp = since.toUtc().toIso8601String().substring(0, 19);
    for (var page = 0; page < maxPages; page++) {
      final json = await _get('/chapter', {
        'limit': '100',
        'offset': '${page * 100}',
        'translatedLanguage[]': [lang],
        'readableAtSince': stamp,
        'order[readableAt]': 'desc',
        'includes[]': const ['scanlation_group'],
        'contentRating[]': contentRatings,
      });
      final data = (json['data'] as List? ?? const []);
      for (final d in data) {
        if (d is! Map) continue;
        final map = d.cast<String, dynamic>();
        final c = parseChapter(map);
        if (c == null) continue;
        String? manga;
        for (final r in (map['relationships'] as List? ?? const [])) {
          if (r is Map && r['type'] == 'manga' && r['id'] is String) manga = r['id'] as String;
        }
        if (manga != null) out.add((manga, c));
      }
      final total = (json['total'] as int?) ?? 0;
      if (data.length < 100 || (page + 1) * 100 >= total) break;
    }
    return out;
  }

  /// Series records (title, cover, type) for up to 100 ids per request.
  Future<Map<String, WorkInfo>> worksByIds(List<String> ids) async {
    final out = <String, WorkInfo>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final json = await _get('/manga', {
        'ids[]': chunk,
        'limit': '100',
        'includes[]': const ['cover_art'],
        'contentRating[]': contentRatings,
      });
      for (final d in (json['data'] as List? ?? const [])) {
        if (d is! Map || d['id'] is! String) continue;
        out[d['id'] as String] = parseManga(d.cast<String, dynamic>());
      }
    }
    return out;
  }

  @override
  Future<List<PageRef>> getPages(SourceChapter chapter) async {
    if (chapter.isExternal) {
      throw const SourceException(
        'Ce chapitre est publié sur le site officiel de l\'éditeur.',
      );
    }
    try {
      final json = await _get('/at-home/server/${chapter.chapterId}');
      return parseAtHome(json);
    } on SourceException catch (e) {
      if (e.statusCode == 404) {
        throw const SourceException(
          'Images introuvables sur MangaDex (404). Ce chapitre peut etre '
          'heberge chez un editeur ou ne plus etre disponible. '
          'Essaye une autre version du chapitre.',
          statusCode: 404,
        );
      }
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Analyse des réponses (publique pour les tests)
  // -------------------------------------------------------------------------

  static Map<String, String> _strMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final e in value.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }

  static String _statusLabel(String? s) => switch (s) {
        'ongoing' => 'En cours',
        'completed' => 'Terminé',
        'hiatus' => 'En pause',
        'cancelled' => 'Annulé',
        _ => 'Inconnu',
      };

  static ContentType _typeFromOriginal(String? lang) => switch (lang) {
        'ko' || 'ko-ro' => ContentType.manhwa,
        'zh' || 'zh-hk' || 'zh-ro' => ContentType.manhua,
        'ja' || 'ja-ro' => ContentType.manga,
        _ => ContentType.other,
      };

  static WorkInfo parseManga(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final a = (data['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};

    final titles = _strMap(a['title']);
    final alt = <String>[];
    for (final m in (a['altTitles'] as List? ?? const [])) {
      alt.addAll(_strMap(m).values);
    }
    String? altEn;
    for (final m in (a['altTitles'] as List? ?? const [])) {
      final en = _strMap(m)['en'];
      if (en != null) {
        altEn = en;
        break;
      }
    }
    final title = titles['en'] ?? altEn ?? titles.values.firstOrNull ?? 'Sans titre';

    final desc = _strMap(a['description']);
    final description = (desc['fr'] ?? desc['en'] ?? desc.values.firstOrNull ?? '')
        .trim();

    String? cover;
    final authors = <String>[];
    for (final r in (data['relationships'] as List? ?? const [])) {
      if (r is! Map) continue;
      final type = r['type'];
      final attrs = (r['attributes'] as Map?)?.cast<String, dynamic>();
      if (type == 'cover_art' && attrs != null) {
        final file = attrs['fileName'];
        if (file is String) cover = '$uploadsBase/covers/$id/$file.512.jpg';
      } else if ((type == 'author' || type == 'artist') && attrs != null) {
        final n = attrs['name'];
        if (n is String && !authors.contains(n)) authors.add(n);
      }
    }

    final tags = <String>[];
    var longStrip = false;
    for (final t in (a['tags'] as List? ?? const [])) {
      if (t is! Map) continue;
      final name = _strMap((t['attributes'] as Map?)?['name'])['en'];
      if (name == null) continue;
      if (name == 'Long Strip') longStrip = true;
      tags.add(name);
    }

    final langs = (a['availableTranslatedLanguage'] as List? ?? const [])
        .whereType<String>()
        .toList();

    return WorkInfo(
      id: 'mangadex:$id',
      title: title,
      altTitles: alt.where((t) => t != title).toSet().take(12).toList(),
      description: description,
      coverUrl: cover,
      type: _typeFromOriginal(a['originalLanguage'] as String?),
      publicationStatus: _statusLabel(a['status'] as String?),
      tags: tags,
      year: a['year'] as int?,
      authors: authors,
      languages: langs,
      longStrip: longStrip,
      links: [SourceLink(sourceId: 'mangadex', workId: id)],
      lastChapter: a['lastChapter'] as String?,
    );
  }

  static SourceChapter? parseChapter(Map<String, dynamic> data) {
    final id = data['id'];
    final a = (data['attributes'] as Map?)?.cast<String, dynamic>();
    if (id is! String || a == null) return null;

    final pages = (a['pages'] as int?) ?? 0;
    final external = a['externalUrl'] as String?;
    if (pages == 0 && external == null) return null;

    var group = 'Groupe inconnu';
    for (final r in (data['relationships'] as List? ?? const [])) {
      if (r is Map && r['type'] == 'scanlation_group') {
        final n = (r['attributes'] as Map?)?['name'];
        if (n is String) {
          group = n;
          break;
        }
      }
    }

    final published = a['readableAt'] ?? a['publishAt'];
    return SourceChapter(
      sourceId: 'mangadex',
      chapterId: id,
      key: ChapterKey.parse(a['chapter'] as String?),
      lang: (a['translatedLanguage'] as String?) ?? 'en',
      group: group,
      title: a['title'] as String?,
      pages: pages,
      externalUrl: external,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
      volume: a['volume'] as String?,
    );
  }

  static List<PageRef> parseAtHome(Map<String, dynamic> json) {
    final base = json['baseUrl'];
    final chapter = (json['chapter'] as Map?)?.cast<String, dynamic>();
    if (base is! String || chapter == null) {
      throw const SourceException('Serveur d\'images MangaDex indisponible.');
    }
    final hash = chapter['hash'] as String;
    final data = (chapter['data'] as List? ?? const []).whereType<String>().toList();
    final saver =
        (chapter['dataSaver'] as List? ?? const []).whereType<String>().toList();
    return [
      for (var i = 0; i < data.length; i++)
        PageRef(
          '$base/data/$hash/${data[i]}',
          fallbackUrl:
              i < saver.length ? '$base/data-saver/$hash/${saver[i]}' : null,
        ),
    ];
  }
}
