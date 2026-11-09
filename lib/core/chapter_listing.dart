import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

import '../engine/http/html_extract.dart';
import 'chapter_key.dart';
import 'models.dart';
import 'source_catalog.dart';
import 'source_health.dart';

/// A chapter *listing*, not a readable chapter. This only observes links that
/// the publisher/server openly returns in a work's HTML page. It does not
/// request page images, execute scripts, log in, or bypass access controls.
class ChapterListing {
  const ChapterListing({required this.key, required this.url});
  final ChapterKey key;
  final String url;
}

class ListingUnavailable implements Exception {
  const ListingUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Shared HTML detector. A link is accepted only when its label or URL
/// explicitly identifies a chapter/episode AND it remains on the source host.
/// Ambiguous links are ignored rather than shown as confirmed releases.
class ChapterListingParser {
  static final _chapter = RegExp(
    r'(?:chapter|chapitre|chap\.?|ch\.?|episode|épisode|ep\.?)\s*[:#\-_/ ]*\s*(\d{1,5}(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  );
  static final _slugChapter = RegExp(
    r'(?:^|[\-_/])(?:chapter|chapitre|chap|ch|episode|ep)[\-_/]*(\d{1,5}(?:[.,\-]\d{1,2})?)(?:$|[\-_/.])',
    caseSensitive: false,
  );

  static List<ChapterListing> parseListing(
    String pageHtml, {
    required String pageUrl,
    required CatalogSite site,
    int maxLinks = 1500,
  }) {
    final page = Uri.tryParse(pageUrl);
    if (page == null || !site.accepts(pageUrl)) {
      throw const ListingUnavailable('Adresse de fiche non autorisee.');
    }
    if (pageHtml.trim().isEmpty) {
      throw const ListingUnavailable('Page vide.');
    }
    final doc = html.parse(pageHtml);
    final sample = (doc.querySelector('title')?.text ?? '').toLowerCase();
    final bodyText = doc.body?.text ?? '';
    final bodyStart = bodyText.length > 1200
        ? bodyText.substring(0, 1200) : bodyText;
    final challengeText = '$sample $bodyStart'.toLowerCase();
    if (challengeText.contains('just a moment') ||
        challengeText.contains('checking your browser') ||
        challengeText.contains('access denied') ||
        challengeText.contains('ssl handshake failed') ||
        challengeText.contains('verify you are human')) {
      throw const ListingUnavailable('Acces bloque ou verification humaine requise.');
    }
    final found = <String, ChapterListing>{};
    // Plusieurs moteurs de lecture utilisent une liste déroulante plutôt que
    // des liens HTML classiques pour naviguer entre les chapitres.
    // On n'exécute aucun JavaScript : uniquement des URL HTTPS du même site.
    for (final element in doc.querySelectorAll(
      'a[href], select option[value], [data-chapter-url]')) {
      if (found.length >= maxLinks) break;
      final href = (element.attributes['href'] ??
        element.attributes['data-chapter-url'] ??
        element.attributes['value'])?.trim();
      if (href == null || href.isEmpty || href.length > 2048 ||
          href.startsWith('#')) continue;
      final target = page.resolve(href);
      if (target == page || !site.accepts(target.toString()) ||
          (target.fragment.isNotEmpty && target.path == page.path)) continue;
      // Pieces of the link separated (« Chapitre 248 » + « 28 oct » must
      // not read « Chapitre 24828 »: rimuscan, The World After the Fall).
      final label = HtmlExtract.spacedText(element);
      final flags = '${element.attributes['class'] ?? ''} '
        '${element.parent?.attributes['class'] ?? ''} $label'.toLowerCase();
      if (RegExp(r'coming soon|upcoming|preview|locked|premium|fast.pass|'
        r'\ba venir\b|bient[oô]t|verrouill').hasMatch(flags)) continue;
      final textual = _chapter.firstMatch(label);
      final slug = _slugChapter.firstMatch(target.path);
      // Some chapter dropdowns store the canonical number on the option.
      final numberAttr = element.attributes['data-chapter-number'];
      final explicit = numberAttr != null &&
          RegExp(r'^\d{1,5}(?:[.,]\d{1,2})?$').hasMatch(numberAttr)
        ? numberAttr : null;
      final number = textual?.group(1) ??
        slug?.group(1)?.replaceAll('-', '.') ?? explicit;
      if (number == null) continue;
      final key = ChapterKey.parse(number.replaceAll(',', '.'));
      if (key.number == null) continue;
      found.putIfAbsent(key.id, () => ChapterListing(
        key: key, url: target.replace(fragment: '').toString(),
      ));
    }
    if (found.isEmpty) {
      throw const ListingUnavailable(
        'Aucun lien de chapitre identifiable dans le HTML public. '
        'Ce site peut charger sa liste en JavaScript ou utiliser une autre structure.',
      );
    }
    return found.values.toList();
  }

  static List<SourceChapter> asChapters(
    List<ChapterListing> links, {
    required String bucketId,
    required String language,
    required String label,
  }) => [
    for (final link in links)
      SourceChapter(
        sourceId: bucketId,
        chapterId: '$bucketId:${link.key.id}',
        key: link.key,
        lang: language,
        group: label,
        externalUrl: link.url,
      ),
  ];
}

/// Lightweight, bounded HTML request with no redirects, no cookies, no
/// JavaScript and no image requests. The caller supplies a saved work URL;
/// checking a site's homepage would often create incorrect associations.
class ChapterListingFetcher {
  const ChapterListingFetcher({
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = 1500000,
  });
  final Duration timeout;
  final int maxBytes;

  Future<List<ChapterListing>> fetch({
    required CatalogSite site,
    required String workUrl,
  }) async {
    if (!site.accepts(workUrl)) {
      throw const ListingUnavailable('Lien hors du domaine de la source.');
    }
    final uri = Uri.parse(workUrl);
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'PazuluReader/0.4.7 (public chapter listing check)';
    try {
      final addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
      if (addresses.isEmpty || addresses.any(isNonPublicIpAddress)) {
        throw const ListingUnavailable('Adresse reseau non publique.');
      }
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403 ||
          response.statusCode == 429) {
        throw ListingUnavailable('Acces restreint (${response.statusCode}).');
      }
      if (response.statusCode != 200) {
        throw ListingUnavailable('Source non verifiable (HTTP ${response.statusCode}).');
      }
      final mime = response.headers.contentType?.mimeType;
      if (mime != 'text/html' && mime != 'application/xhtml+xml') {
        throw const ListingUnavailable('La page ne renvoie pas du HTML.');
      }
      if (response.contentLength > maxBytes) {
        throw const ListingUnavailable('Page trop volumineuse pour un controle leger.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const ListingUnavailable('Page trop volumineuse pour un controle leger.');
        }
        bytes.addAll(chunk);
      }
      return ChapterListingParser.parseListing(
        utf8.decode(bytes, allowMalformed: true),
        pageUrl: workUrl,
        site: site,
      );
    } on ListingUnavailable {
      rethrow;
    } on TimeoutException {
      throw const ListingUnavailable('Controle expire : site trop lent.');
    } on SocketException {
      throw const ListingUnavailable('Impossible de joindre le serveur.');
    } catch (e) {
      throw ListingUnavailable('Controle impossible : $e');
    } finally {
      client.close(force: true);
    }
  }
}
