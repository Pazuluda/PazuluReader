import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'user_sources.dart';

/// Data supplied by the user, not an audited list of working reader adapters.
/// Adding a candidate only adds its URL to the user's catalogue.
class SuggestedSource {
  const SuggestedSource({
    required this.rank,
    required this.url,
    required this.language,
    required this.category,
    required this.reportedStatus,
  });

  final int rank;
  final String url;
  final String language;
  final String category;
  final String reportedStatus;

  String get host => Uri.parse(url).host;
  String get displayName => host.replaceFirst(RegExp(r'^www\.'), '');
  bool get isReportedAccessible => reportedStatus == 'Accueil/catalogue accessible';

  static SuggestedSource fromJson(Map<String, dynamic> data) {
    final url = data['url'];
    final lang = data['language'];
    final rank = data['rank'];
    final status = data['reportedStatus'];
    final category = data['category'];
    if (url is! String || rank is! int || rank <= 0 ||
        (lang != 'fr' && lang != 'en') ||
        status is! String || category is! String) {
      throw const FormatException('Source suggeree invalide.');
    }
    normalizedSourceUri(url); // Reject unsafe hostnames before they reach UI.
    return SuggestedSource(
      rank: rank, url: url, language: lang as String,
      category: category, reportedStatus: status,
    );
  }
}

class SuggestedSourceCatalog {
  const SuggestedSourceCatalog._();

  static List<SuggestedSource> parse(String jsonText) {
    final data = jsonDecode(jsonText);
    if (data is! Map || data['format'] != 'pazulu-suggested-sources' ||
        data['sources'] is! List || (data['sources'] as List).length > 500) {
      throw const FormatException('Catalogue de suggestions non reconnu.');
    }
    final seen = <String>{};
    final out = <SuggestedSource>[];
    for (final item in data['sources'] as List) {
      if (item is! Map) throw const FormatException('Element incorrect.');
      final source = SuggestedSource.fromJson(item.cast<String, dynamic>());
      if (!seen.add(source.host)) continue;
      out.add(source);
    }
    return List<SuggestedSource>.unmodifiable(out);
  }

  static Future<List<SuggestedSource>> load() async => parse(
    await rootBundle.loadString('assets/suggested_sources.json'),
  );
}
