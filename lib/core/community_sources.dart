import 'source_catalog.dart';
import 'suggested_sources.dart';

/// The user's 200-domain directory is a *directory of addresses*, not 200
/// verified native reader plugins. Stable IDs allow previously linked works
/// to survive future releases without converting the directory into downloads.
class CommunitySourceDirectory {
  const CommunitySourceDirectory._();

  static List<CatalogSite> fromSuggestions(List<SuggestedSource> suggestions) {
    final known = <String>{
      for (final item in catalogSites) _host(item.home),
      for (final item in archivedCatalogSites) _host(item.home),
    };
    final result = <CatalogSite>[];
    for (final item in suggestions) {
      if (!known.add(_host(item.url))) continue;
      result.add(CatalogSite(
        'directory_${item.rank.toString().padLeft(3, '0')}',
        item.displayName,
        item.url,
        [item.language],
        SiteIntegration.website,
      ));
    }
    return List<CatalogSite>.unmodifiable(result);
  }

  static String _host(String url) => Uri.parse(url).host.toLowerCase()
      .replaceFirst(RegExp(r'^www\.'), '');
}
