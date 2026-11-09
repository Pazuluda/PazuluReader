/// Répertoire demandé par l'utilisateur : accès aux sites, séparé des
/// connecteurs d'extraction. Seul MangaDex dispose actuellement d'un connecteur
/// de chapitres et de pages vérifié dans l'application.
enum SiteIntegration { chapterConnector, website }

class CatalogSite {
  const CatalogSite(this.id, this.title, this.home, this.languages, this.integration);

  final String id;
  final String title;
  final String home;
  final List<String> languages;
  final SiteIntegration integration;

  bool get hasReaderConnector => integration == SiteIntegration.chapterConnector;

  /// Garde les liens de fiches sur le domaine choisi (sans javascript:, etc.).
  bool accepts(String candidate) {
    final uri = Uri.tryParse(candidate.trim());
    final base = Uri.parse(home);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.host.isEmpty || uri.hasPort) return false;
    final host = uri.host.toLowerCase();
    final domain = base.host.toLowerCase();
    // www et sous-domaines sont autorisés pour les chemins de lecture.
    final root = domain.startsWith('www.') ? domain.substring(4) : domain;
    return host == root || host.endsWith('.$root');
  }
}

const catalogSites = <CatalogSite>[
  CatalogSite('manhuaus', 'ManhuaUS', 'https://manhuaus.com/', ['en'], SiteIntegration.website),
  CatalogSite('asurascans', 'AsuraScans', 'https://asurascans.com/', ['en'], SiteIntegration.website),
  CatalogSite('aethonwebcomics', 'Aethon Webcomics', 'https://aethonwebcomics.com/', ['en'], SiteIntegration.website),
  CatalogSite('scanmanga', 'Scan-Manga', 'https://www.scan-manga.com/', ['fr'], SiteIntegration.website),
  CatalogSite('thunderscans', 'EN-ThunderScans', 'https://en-thunderscans.com/', ['en'], SiteIntegration.website),
  CatalogSite('toongod', 'ToonGod', 'https://www.toongod.org/', ['en'], SiteIntegration.website),
  CatalogSite('swordhound', 'Swordhound', 'https://w28.swordhound.com/', ['en'], SiteIntegration.website),
  CatalogSite('sssclasshunter', 'SSS-Class Hunter', 'https://sss.sssclasshunter.com/', ['en'], SiteIntegration.website),
  CatalogSite('manhuatop', 'ManhuaTop', 'https://manhuatop.org/', ['en'], SiteIntegration.website),
  CatalogSite('mangadex', 'MangaDex', 'https://mangadex.org/', ['en', 'fr'], SiteIntegration.chapterConnector),
  CatalogSite('kingofshojo', 'KingofShojo', 'https://kingofshojo.com/', ['en'], SiteIntegration.website),
  CatalogSite('webtoon_fr', 'WEBTOON FR', 'https://www.webtoons.com/fr/', ['fr'], SiteIntegration.website),
  CatalogSite('webtoon_en', 'WEBTOON EN', 'https://www.webtoons.com/en/', ['en'], SiteIntegration.website),
];

/// Conserve les identifiants historiques pour les liens deja sauvegardes.
/// Les deux sources ne sont plus proposees ni surveillees par defaut.
const archivedCatalogSites = <CatalogSite>[
  CatalogSite('manhuafast', 'ManhuaFast', 'https://manhuafast.net/', ['en'], SiteIntegration.website),
  CatalogSite('manhwaclan', 'ManhwaClan', 'https://manhwaclan.com/', ['en'], SiteIntegration.website),
];

CatalogSite? catalogSiteById(String id) {
  for (final site in [...catalogSites, ...archivedCatalogSites]) {
    if (site.id == id) return site;
  }
  return null;
}
