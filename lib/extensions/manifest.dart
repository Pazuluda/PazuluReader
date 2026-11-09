import 'dart:convert';

import '../engine/engine_version.dart';

/// How an extension obtains content.
enum ExtensionTransport {
  /// Compiled Dart adapter bundled with the engine (Level 2), e.g. MangaDex.
  native,

  /// Declarative HTTP/HTML rules (Level 1).
  html,

  /// HTML rules + hidden WebView2 rendering for pages that need JavaScript.
  browser,
}

/// Real validation level of a connector, shown everywhere it is listed.
enum ValidationLevel {
  verifiedLive,
  verifiedFixtureOnly,
  implementedUntested,
  metadataOnly,
  unsupported,
}

extension ValidationLevelLabel on ValidationLevel {
  String get code => switch (this) {
        ValidationLevel.verifiedLive => 'VERIFIED_LIVE',
        ValidationLevel.verifiedFixtureOnly => 'VERIFIED_FIXTURE_ONLY',
        ValidationLevel.implementedUntested => 'IMPLEMENTED_UNTESTED',
        ValidationLevel.metadataOnly => 'METADATA_ONLY',
        ValidationLevel.unsupported => 'UNSUPPORTED',
      };

  String get label => switch (this) {
        ValidationLevel.verifiedLive => 'Vérifiée en conditions réelles',
        ValidationLevel.verifiedFixtureOnly => 'Vérifiée sur fixtures uniquement',
        ValidationLevel.implementedUntested => 'Implémentée, non testée en réel',
        ValidationLevel.metadataOnly => 'Métadonnées uniquement',
        ValidationLevel.unsupported => 'Non prise en charge',
      };

  static ValidationLevel parse(String? raw) => switch (raw) {
        'VERIFIED_LIVE' => ValidationLevel.verifiedLive,
        'VERIFIED_FIXTURE_ONLY' => ValidationLevel.verifiedFixtureOnly,
        'METADATA_ONLY' => ValidationLevel.metadataOnly,
        'UNSUPPORTED' => ValidationLevel.unsupported,
        _ => ValidationLevel.implementedUntested,
      };
}

/// Selector set for one HTML family or a domain-specific override.
class HtmlRules {
  const HtmlRules({
    this.family = 'custom',
    this.searchUrl,
    this.searchItem,
    this.searchLink,
    this.searchTitle,
    this.searchCover,
    this.workTitle,
    this.workDescription,
    this.workCover,
    this.chapterItem,
    this.chapterLink,
    this.chapterTitle,
    this.chapterVolume,
    this.pageImages = const [],
    this.useTsReader = false,
    this.useMadaraPreloaded = false,
    this.pageCounter,
    this.restrictedTexts = const [],
    this.seriesPathPrefix,
    this.chapterPathPattern,
  });

  final String family;

  /// `https://host/?s={query}` — {query} is URL-encoded by the engine.
  final String? searchUrl;
  final String? searchItem;
  final String? searchLink;
  final String? searchTitle;
  final String? searchCover;
  final String? workTitle;
  final String? workDescription;
  final String? workCover;
  final String? chapterItem;
  final String? chapterLink;
  final String? chapterTitle;
  final String? chapterVolume;
  final List<String> pageImages;
  final bool useTsReader;
  final bool useMadaraPreloaded;

  /// CSS selector of a "3 / 14" counter, when the site publishes one.
  final String? pageCounter;

  /// Site-specific phrases meaning "this chapter is locked".
  final List<String> restrictedTexts;

  /// Work URLs must start with this path ("/manga/", "/catalogue/").
  final String? seriesPathPrefix;

  /// Optional regexp a chapter URL path must match.
  final String? chapterPathPattern;

  /// Built-in families. Declarative manifests only override what differs.
  static HtmlRules family_(String name) => switch (name) {
        'madara' => const HtmlRules(
            family: 'madara',
            searchUrl: '/?s={query}&post_type=wp-manga',
            searchItem: '.c-tabs-item__content, .page-item-detail, .row.c-tabs-item__content',
            searchLink: '.post-title a, h3 a, .tab-thumb a',
            searchTitle: '.post-title a, h3 a',
            searchCover: 'img',
            workTitle: '.post-title h1, h1',
            workDescription: '.description-summary, .summary__content, .manga-excerpt',
            workCover: '.summary_image img',
            chapterItem: 'li.wp-manga-chapter',
            chapterLink: 'a',
            chapterTitle: 'a',
            pageImages: ['.reading-content .page-break img', '.reading-content img',
              'img.wp-manga-chapter-img', '.reading-content picture'],
            useMadaraPreloaded: true,
            seriesPathPrefix: '/',
          ),
        'mangathemesia' => const HtmlRules(
            family: 'mangathemesia',
            searchUrl: '/?s={query}',
            searchItem: '.listupd .bs, .listupd .bsx, .bsx',
            searchLink: 'a',
            searchTitle: '.tt, .ntitle, a',
            searchCover: 'img',
            workTitle: 'h1.entry-title, .entry-title, h1',
            workDescription: '.entry-content[itemprop=description], .synp .entry-content, .summary',
            workCover: '.thumb img, .thumbook img',
            chapterItem: '#chapterlist li, .eplister li, .cl li',
            chapterLink: 'a',
            chapterTitle: '.chapternum, .epl-num, a',
            pageImages: ['#readerarea img', '#readerarea picture', '.rdminimal img'],
            useTsReader: true,
            pageCounter: '.ts-select-paged + .npv, .page-number',
          ),
        _ => const HtmlRules(),
      };

  HtmlRules merge(Map<String, dynamic> o) {
    List<String> list(String key, List<String> fallback) {
      final v = o[key];
      if (v is! List) return fallback;
      return [for (final s in v) if (s is String) s];
    }
    String? str(String key, String? fallback) {
      final v = o[key];
      return v is String ? v : fallback;
    }
    bool flag(String key, bool fallback) {
      final v = o[key];
      return v is bool ? v : fallback;
    }
    return HtmlRules(
      family: family,
      searchUrl: str('searchUrl', searchUrl),
      searchItem: str('searchItem', searchItem),
      searchLink: str('searchLink', searchLink),
      searchTitle: str('searchTitle', searchTitle),
      searchCover: str('searchCover', searchCover),
      workTitle: str('workTitle', workTitle),
      workDescription: str('workDescription', workDescription),
      workCover: str('workCover', workCover),
      chapterItem: str('chapterItem', chapterItem),
      chapterLink: str('chapterLink', chapterLink),
      chapterTitle: str('chapterTitle', chapterTitle),
      chapterVolume: str('chapterVolume', chapterVolume),
      pageImages: list('pageImages', pageImages),
      useTsReader: flag('useTsReader', useTsReader),
      useMadaraPreloaded: flag('useMadaraPreloaded', useMadaraPreloaded),
      pageCounter: str('pageCounter', pageCounter),
      restrictedTexts: list('restrictedTexts', restrictedTexts),
      seriesPathPrefix: str('seriesPathPrefix', seriesPathPrefix),
      chapterPathPattern: str('chapterPathPattern', chapterPathPattern),
    );
  }

  Map<String, dynamic> toJson() => {
        'family': family,
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (searchItem != null) 'searchItem': searchItem,
        if (searchLink != null) 'searchLink': searchLink,
        if (searchTitle != null) 'searchTitle': searchTitle,
        if (searchCover != null) 'searchCover': searchCover,
        if (workTitle != null) 'workTitle': workTitle,
        if (workDescription != null) 'workDescription': workDescription,
        if (workCover != null) 'workCover': workCover,
        if (chapterItem != null) 'chapterItem': chapterItem,
        if (chapterLink != null) 'chapterLink': chapterLink,
        if (chapterTitle != null) 'chapterTitle': chapterTitle,
        if (chapterVolume != null) 'chapterVolume': chapterVolume,
        'pageImages': pageImages,
        'useTsReader': useTsReader,
        'useMadaraPreloaded': useMadaraPreloaded,
        if (pageCounter != null) 'pageCounter': pageCounter,
        if (restrictedTexts.isNotEmpty) 'restrictedTexts': restrictedTexts,
        if (seriesPathPrefix != null) 'seriesPathPrefix': seriesPathPrefix,
        if (chapterPathPattern != null) 'chapterPathPattern': chapterPathPattern,
      };
}

class ExtensionCapabilities {
  const ExtensionCapabilities({this.search = false, this.chapters = false,
    this.pages = false, this.latest = false});

  final bool search;
  final bool chapters;
  final bool pages;
  final bool latest;

  Map<String, bool> toJson() =>
      {'search': search, 'chapters': chapters, 'pages': pages, 'latest': latest};
}

class ExtensionTest {
  const ExtensionTest({required this.kind, this.query, this.workUrl, this.chapterUrl,
    this.expectedPages});

  /// search / chapters / pages
  final String kind;
  final String? query;
  final String? workUrl;
  final String? chapterUrl;
  final int? expectedPages;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (query != null) 'query': query,
        if (workUrl != null) 'workUrl': workUrl,
        if (chapterUrl != null) 'chapterUrl': chapterUrl,
        if (expectedPages != null) 'expectedPages': expectedPages,
      };
}

/// Versioned extension manifest (schemaVersion 2). Data only — never code.
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.languages,
    required this.contentTypes,
    required this.hosts,
    required this.capabilities,
    required this.transport,
    required this.minimumEngineVersion,
    this.homeUrl,
    this.nativeAdapter,
    this.paginationMode = 'auto',
    this.readingDirection = 'auto',
    this.imageMode = 'referer',
    this.imageHosts = const [],
    this.requestsPerMinute = 30,
    this.maxConcurrent = 2,
    this.validation = ValidationLevel.implementedUntested,
    this.html,
    this.tests = const [],
    this.notes,
    this.enabledByDefault = true,
    this.raw = const {},
  });

  static const int schemaVersion = 2;
  static final RegExp idPattern = RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+){1,6}$');
  static final RegExp hostPattern = RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$');
  static const knownLanguages = {
    'fr', 'en', 'es', 'es-la', 'pt', 'pt-br', 'it', 'de', 'ja', 'ko', 'zh',
    'id', 'vi', 'th', 'ru', 'ar', 'tr', 'pl'};
  static const knownContentTypes = {
    'manga', 'manhwa', 'manhua', 'webtoon', 'comic', 'novel', 'webnovel'};
  static const nativeAdapters = {'mangadex', 'peppercarrot', 'sushiscan_net'};

  final String id;
  final String name;
  final String version;
  final List<String> languages;
  final List<String> contentTypes;
  final List<String> hosts;
  final ExtensionCapabilities capabilities;
  final ExtensionTransport transport;
  final String minimumEngineVersion;
  final String? homeUrl;
  final String? nativeAdapter;

  /// auto / vertical / horizontal / paged
  final String paginationMode;

  /// auto / ltr / rtl / vertical
  final String readingDirection;

  /// direct / referer (Referer = chapter URL)
  final String imageMode;

  /// CDN hosts allowed for page images in addition to [hosts].
  final List<String> imageHosts;
  final int requestsPerMinute;
  final int maxConcurrent;
  final ValidationLevel validation;
  final HtmlRules? html;
  final List<ExtensionTest> tests;
  final String? notes;

  /// Bundled-but-unverified profiles ship disabled until the user tests them.
  final bool enabledByDefault;

  /// Original JSON, kept for export and integrity hashing.
  final Map<String, dynamic> raw;

  SemVer get semver => SemVer.parse(version);

  bool get engineCompatible => engineSatisfies(minimumEngineVersion);

  List<String> get allImageHosts => {...hosts, ...imageHosts}.toList();

  String get home => homeUrl ?? 'https://${hosts.first}/';

  /// Parses and validates. Throws [FormatException] with a French message
  /// describing the first problem.
  static ExtensionManifest parse(Object? json) {
    if (json is String) {
      if (json.length > 256 * 1024) {
        throw const FormatException('Manifeste trop volumineux.');
      }
      json = jsonDecode(json);
    }
    if (json is! Map) throw const FormatException('Manifeste JSON attendu.');
    final m = json.cast<String, dynamic>();
    if (m['format'] == 'pazulu-source' && m['manifest'] is Map) {
      return parse(m['manifest']);
    }
    Never fail(String message) => throw FormatException(message);

    if (m['schemaVersion'] != schemaVersion) {
      fail('schemaVersion $schemaVersion attendu.');
    }
    final id = m['id'];
    if (id is! String || !idPattern.hasMatch(id) || id.length > 64) {
      fail('Identifiant invalide (ex. "pazulu.monsite").');
    }
    final name = m['name'];
    if (name is! String || name.trim().isEmpty || name.length > 80) {
      fail('Nom manquant ou trop long.');
    }
    final version = m['version'];
    if (version is! String || SemVer.tryParse(version) == null) {
      fail('Version semver attendue (ex. 1.0.0).');
    }
    List<String> strings(String key, {int max = 20}) {
      final v = m[key];
      if (v is! List || v.length > max || v.any((e) => e is! String)) {
        throw FormatException('"$key" doit être une liste de textes.');
      }
      return [for (final e in v) (e as String).trim().toLowerCase()];
    }

    final languages = strings('languages');
    if (languages.isEmpty || languages.any((l) => !knownLanguages.contains(l))) {
      fail('Langues inconnues ou absentes.');
    }
    final types = strings('contentTypes');
    if (types.isEmpty || types.any((t) => !knownContentTypes.contains(t))) {
      fail('Types de contenu inconnus ou absents.');
    }
    final hosts = strings('hosts', max: 6);
    if (hosts.isEmpty) fail('Au moins un domaine autorisé est requis.');
    for (final h in [...hosts, ...strings2(m, 'imageHosts')]) {
      if (!_validHost(h)) fail('Domaine refusé : $h');
    }
    final transportName = m['transport'];
    final transport = switch (transportName) {
      'native' => ExtensionTransport.native,
      'html' => ExtensionTransport.html,
      'browser' => ExtensionTransport.browser,
      _ => null,
    };
    if (transport == null) {
      fail('Transport inconnu (native, html ou browser).');
    }
    final minimum = m['minimumEngineVersion'];
    if (minimum is! String || SemVer.tryParse(minimum) == null) {
      fail('minimumEngineVersion invalide.');
    }
    String? adapter;
    if (transport == ExtensionTransport.native) {
      final declared = m['nativeAdapter'];
      adapter = declared is String ? declared : null;
      if (adapter == null || !nativeAdapters.contains(adapter)) {
        fail('Adaptateur natif inconnu : seuls les adaptateurs compilés '
            'avec Pazulu sont acceptés.');
      }
    }
    final home = m['homeUrl'];
    if (home != null) {
      final uri = home is String ? Uri.tryParse(home) : null;
      if (uri == null || uri.scheme != 'https' || uri.hasPort ||
          uri.userInfo.isNotEmpty || !_hostIn(uri.host, hosts)) {
        fail('homeUrl doit être en HTTPS sur un domaine déclaré.');
      }
    }
    final capsRaw = m['capabilities'];
    if (capsRaw is! Map) fail('"capabilities" manquant.');
    bool cap(String k) => capsRaw[k] == true;
    final caps = ExtensionCapabilities(search: cap('search'), chapters: cap('chapters'),
        pages: cap('pages'), latest: cap('latest'));

    String choice(String key, Set<String> allowed, String fallback) {
      final v = m[key];
      if (v == null) return fallback;
      if (v is! String || !allowed.contains(v)) {
        throw FormatException('"$key" doit valoir ${allowed.join(', ')}.');
      }
      return v;
    }

    final pagination = choice('paginationMode', {'auto', 'vertical', 'horizontal', 'paged'}, 'auto');
    final direction = choice('readingDirection', {'auto', 'ltr', 'rtl', 'vertical'}, 'auto');
    final imageMode = choice('imageMode', {'direct', 'referer'}, 'referer');

    var rpm = 30;
    var concurrent = 2;
    final limits = m['rateLimit'];
    if (limits != null) {
      if (limits is! Map) fail('"rateLimit" invalide.');
      final r = limits['requestsPerMinute'];
      final c = limits['maxConcurrent'];
      if (r != null && (r is! int || r < 1 || r > 300)) fail('requestsPerMinute 1..300.');
      if (c != null && (c is! int || c < 1 || c > 4)) fail('maxConcurrent 1..4.');
      if (r is int) rpm = r;
      if (c is int) concurrent = c;
    }

    HtmlRules? html;
    if (transport == ExtensionTransport.html || transport == ExtensionTransport.browser) {
      final rules = m['html'];
      if (rules is! Map) fail('Section "html" requise pour ce transport.');
      final r = rules.cast<String, dynamic>();
      final familyName = r['family'] is String ? r['family'] as String : 'custom';
      if (!{'madara', 'mangathemesia', 'custom'}.contains(familyName)) {
        fail('Famille HTML inconnue : $familyName');
      }
      for (final entry in r.entries) {
        _checkSelectorValue(entry.key, entry.value);
      }
      html = HtmlRules.family_(familyName).merge(r);
      final search = html.searchUrl;
      if (search != null && search.startsWith('http')) {
        final uri = Uri.tryParse(search.replaceAll('{query}', 'x'));
        if (uri == null || uri.scheme != 'https' || !_hostIn(uri.host, hosts)) {
          fail('searchUrl hors des domaines déclarés.');
        }
      }
      if (html.chapterPathPattern != null) {
        try {
          RegExp(html.chapterPathPattern!);
        } catch (_) {
          fail('chapterPathPattern n\'est pas une expression valide.');
        }
      }
      if (caps.pages && html.pageImages.isEmpty && !html.useTsReader &&
          !html.useMadaraPreloaded) {
        fail('Aucune règle d\'extraction de pages.');
      }
    }

    final tests = <ExtensionTest>[];
    final rawTests = m['tests'];
    if (rawTests is List) {
      for (final t in rawTests.take(10)) {
        if (t is! Map || t['kind'] is! String) continue;
        tests.add(ExtensionTest(
          kind: t['kind'] as String,
          query: t['query'] is String ? t['query'] as String : null,
          workUrl: t['workUrl'] is String ? t['workUrl'] as String : null,
          chapterUrl: t['chapterUrl'] is String ? t['chapterUrl'] as String : null,
          expectedPages: t['expectedPages'] is int ? t['expectedPages'] as int : null,
        ));
      }
    }

    return ExtensionManifest(
      id: id,
      name: name.trim(),
      version: version,
      languages: languages,
      contentTypes: types,
      hosts: hosts,
      capabilities: caps,
      transport: transport,
      minimumEngineVersion: minimum,
      homeUrl: home is String ? home : null,
      nativeAdapter: adapter,
      paginationMode: pagination,
      readingDirection: direction,
      imageMode: imageMode,
      imageHosts: strings2(m, 'imageHosts'),
      requestsPerMinute: rpm,
      maxConcurrent: concurrent,
      validation: ValidationLevelLabel.parse(
          m['validation'] is String ? m['validation'] as String : null),
      html: html,
      tests: tests,
      notes: m['notes'] is String ? m['notes'] as String : null,
      enabledByDefault: m['enabledByDefault'] != false,
      raw: Map<String, dynamic>.unmodifiable(m),
    );
  }

  static List<String> strings2(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return const [];
    if (v is! List || v.length > 8 || v.any((e) => e is! String)) {
      throw FormatException('"$key" doit être une liste de domaines.');
    }
    return [for (final e in v) (e as String).trim().toLowerCase()];
  }

  static bool _validHost(String h) =>
      h.length <= 253 && hostPattern.hasMatch(h) && !h.endsWith('.local') &&
      !h.endsWith('.localhost') && !h.endsWith('.internal') &&
      !RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(h);

  static bool _hostIn(String host, List<String> hosts) {
    final h = host.toLowerCase();
    return hosts.any((d) => h == d || h.endsWith('.$d'));
  }

  /// Selectors are CSS for package:html, never script. Reject markup,
  /// script-ish payloads and absurd sizes.
  static void _checkSelectorValue(String key, Object? value) {
    void check(String s) {
      if (s.length > 300 || s.contains('<') || s.contains('>>') ||
          s.toLowerCase().contains('javascript:') || s.contains('\u0000')) {
        throw FormatException('Valeur refusée pour "$key".');
      }
    }
    if (value is String) {
      check(value);
    } else if (value is List) {
      if (value.length > 20) throw FormatException('"$key" : trop d\'éléments.');
      for (final v in value) {
        if (v is! String) throw FormatException('"$key" : textes attendus.');
        check(v);
      }
    } else if (value is! bool && value != null) {
      throw FormatException('"$key" : type non accepté.');
    }
  }

  Map<String, dynamic> toJson() => raw.isNotEmpty ? Map<String, dynamic>.of(raw) : {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'version': version,
        'languages': languages,
        'contentTypes': contentTypes,
        'hosts': hosts,
        'capabilities': capabilities.toJson(),
        'transport': transport.name,
        'minimumEngineVersion': minimumEngineVersion,
        if (homeUrl != null) 'homeUrl': homeUrl,
        if (nativeAdapter != null) 'nativeAdapter': nativeAdapter,
        'paginationMode': paginationMode,
        'readingDirection': readingDirection,
        'imageMode': imageMode,
        if (imageHosts.isNotEmpty) 'imageHosts': imageHosts,
        'rateLimit': {'requestsPerMinute': requestsPerMinute, 'maxConcurrent': maxConcurrent},
        'validation': validation.code,
        if (html != null) 'html': html!.toJson(),
        if (tests.isNotEmpty) 'tests': tests.map((t) => t.toJson()).toList(),
        if (notes != null) 'notes': notes,
      };
}
