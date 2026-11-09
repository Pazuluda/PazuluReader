import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/models.dart';
import '../availability.dart';
import 'access_detector.dart';
import 'image_sniffer.dart';

/// Result of fetching the first bytes of one page.
class PageProbe {
  const PageProbe({
    required this.index,
    required this.url,
    this.status,
    this.contentType,
    this.sniff,
    this.error,
    this.contentHash,
    this.finalHost,
    this.complete = false,
  });

  final int index;
  final String url;
  final int? status;
  final String? contentType;
  final ImageSniff? sniff;
  final String? error;

  /// SHA-256 of the probed bytes (first chunk) to spot repeated images.
  final String? contentHash;
  final String? finalHost;

  /// The hash covers the whole file (offline bytes, small images). Hashes
  /// of truncated probes can only *warn* about repeated images.
  final bool complete;

  /// Same probe for a page that moved in the list (edge images removed).
  PageProbe withIndex(int newIndex) => PageProbe(
        index: newIndex,
        url: url,
        status: status,
        contentType: contentType,
        sniff: sniff,
        error: error,
        contentHash: contentHash,
        finalHost: finalHost,
        complete: complete,
      );

  static PageProbe fromBytes(int index, String url, int status, Uint8List bytes,
      {String? contentType, String? finalHost, bool complete = false}) {
    return PageProbe(
      index: index,
      url: url,
      status: status,
      contentType: contentType,
      sniff: ImageSniff.inspect(bytes, contentType: contentType),
      contentHash: bytes.isEmpty ? null : sha256.convert(bytes).toString(),
      finalHost: finalHost,
      complete: complete,
    );
  }
}

/// Per-chapter tolerance. Strict by default; legitimate exceptions are
/// declared by the connector (webtoon slices, colour inserts, credits page).
class ValidationPolicy {
  const ValidationPolicy({
    this.minWidth = 200,
    this.minHeight = 200,
    this.verticalStrip = false,
    this.allowedImageHosts = const [],
    this.allowSmallPages = 0,
  });

  final int minWidth;
  final int minHeight;

  /// Webtoon chapters are cut into wide, sometimes very short slices.
  final bool verticalStrip;

  /// When non-empty, page hosts must match one of these (or a subdomain).
  final List<String> allowedImageHosts;

  /// Number of pages allowed below the size thresholds (credits, end card).
  final int allowSmallPages;

  static const strict = ValidationPolicy();
  static const webtoon = ValidationPolicy(minWidth: 300, minHeight: 40,
      verticalStrip: true, allowSmallPages: 2);
}

/// The Page Validation Engine. A manga page is not "any <img>": URL, host,
/// MIME, HTTP status, real dimensions, duplicates, spinners/logos, paywall
/// and error pages, announced total and order are all checked.
class PageValidationEngine {
  const PageValidationEngine();

  static final RegExp _suspiciousName = RegExp(
      r'(?:^|[/_.-])(?:logo|banner|avatar|icon|favicon|sprite|loading|loader|'
      r'spinner|placeholder|blank|pixel|spacer|lazy|thumb(?:nail)?|ads?|'
      r'advert|promo|discord|patreon|kofi|paypal|watermark-only|readerarea)'
      r'(?:[/_.-]|\d|$)',
      caseSensitive: false);

  /// Structural checks that need no network. Returns issues; fatal issues
  /// mean the list must not be shown.
  List<ValidationIssue> structural(List<PageRef> pages, {
    int? announcedTotal,
    ValidationPolicy policy = ValidationPolicy.strict,
    bool offline = false,
  }) {
    final issues = <ValidationIssue>[];
    if (pages.isEmpty) {
      issues.add(const ValidationIssue('empty', 'Aucune page retournée.', fatal: true));
      return issues;
    }
    final seen = <String>{};
    var suspicious = 0;
    for (var i = 0; i < pages.length; i++) {
      final raw = pages[i].url.trim();
      if (!seen.add(raw)) {
        issues.add(ValidationIssue('duplicate_url', 'Adresse répétée.', pageIndex: i, fatal: true));
        continue;
      }
      if (offline) {
        if (!RegExp(r'^hors-ligne:\d+$').hasMatch(raw)) {
          issues.add(ValidationIssue('bad_local', 'Page locale non reconnue.', pageIndex: i, fatal: true));
        }
        continue;
      }
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
          uri.hasPort || uri.userInfo.isNotEmpty) {
        issues.add(ValidationIssue('insecure_url', 'Adresse non HTTPS ou invalide.',
            pageIndex: i, fatal: true));
        continue;
      }
      if (_isLocalHost(uri.host)) {
        issues.add(ValidationIssue('local_host', 'Hôte local refusé.', pageIndex: i, fatal: true));
        continue;
      }
      if (policy.allowedImageHosts.isNotEmpty &&
          !policy.allowedImageHosts.any((h) => _hostMatches(uri.host, h))) {
        issues.add(ValidationIssue('foreign_host', 'Hôte d\'image non déclaré (${uri.host}).',
            pageIndex: i, fatal: true));
        continue;
      }
      final path = uri.path.toLowerCase();
      if (path.endsWith('.svg') || path.endsWith('.ico')) {
        issues.add(ValidationIssue('not_page_format', 'Format non utilisé pour une planche.',
            pageIndex: i, fatal: true));
        continue;
      }
      if (_suspiciousName.hasMatch(path)) {
        suspicious++;
        issues.add(ValidationIssue('suspicious_name',
            'Nom d\'image typique d\'un logo ou d\'un chargement.', pageIndex: i));
      }
    }
    if (suspicious > 0 && suspicious == pages.length) {
      issues.add(const ValidationIssue('all_suspicious',
          'Toutes les images ressemblent à des éléments d\'interface.', fatal: true));
    }
    final total = announcedTotal;
    if (total != null && total > 0 && pages.length > total * 2 + 4) {
      issues.add(ValidationIssue('too_many',
          '${pages.length} images pour $total pages annoncées : ordre incertain.', fatal: true));
    }
    return issues;
  }

  /// Full verdict from structural checks and network probes of some pages.
  ///
  /// [probes] may cover only a sample (first/last pages). Unprobed pages are
  /// counted as structurally valid but the verdict notes it.
  ChapterPages evaluate(List<PageRef> pages, {
    int? announcedTotal,
    List<PageProbe> probes = const [],
    ValidationPolicy policy = ValidationPolicy.strict,
    bool offline = false,
    String transport = 'api',
    Duration? elapsed,
    Map<String, String> imageHeaders = const {},
  }) {
    final issues = structural(pages, announcedTotal: announcedTotal,
        policy: policy, offline: offline);
    final badIndexes = <int>{
      for (final i in issues) if (i.fatal && i.pageIndex != null) i.pageIndex!,
    };
    var access = AccessKind.open;
    var smallPages = 0;
    final hashes = <String, (int, bool)>{};
    for (final probe in probes) {
      final sniff = probe.sniff;
      final status = probe.status;
      if (probe.error != null || status == null) {
        issues.add(ValidationIssue('probe_failed',
            'Image injoignable : ${probe.error ?? 'pas de réponse'}',
            pageIndex: probe.index, fatal: true));
        badIndexes.add(probe.index);
        continue;
      }
      if (status < 200 || status >= 300) {
        final kind = AccessDetector.classifyStatus(status);
        if (kind != AccessKind.open && kind != AccessKind.removed) access = kind;
        issues.add(ValidationIssue('http_$status', 'HTTP $status sur l\'image.',
            pageIndex: probe.index, fatal: true));
        badIndexes.add(probe.index);
        continue;
      }
      if (sniff == null || !sniff.isImage) {
        final text = sniff?.text ?? '';
        final kind = AccessDetector.classifyText(
            sniff?.kind == PayloadKind.html ? AccessDetector.visibleTextOf(text) : text);
        if (kind != AccessKind.open) access = kind;
        issues.add(ValidationIssue('not_image',
            sniff?.kind == PayloadKind.html
                ? 'Page HTML servie à la place d\'une image${kind == AccessKind.open ? '' : ' (${kind.label})'}.'
                : 'Contenu qui n\'est pas une image (${sniff?.kind.name ?? 'inconnu'}).',
            pageIndex: probe.index, fatal: true));
        badIndexes.add(probe.index);
        continue;
      }
      final type = probe.contentType?.toLowerCase();
      if (type != null && type.startsWith('text/')) {
        issues.add(ValidationIssue('mime_mismatch',
            'Type MIME $type pour des octets d\'image.', pageIndex: probe.index));
      }
      if (sniff.format == 'gif' && (sniff.width ?? 0) < 400) {
        issues.add(ValidationIssue('loading_gif', 'GIF de chargement.',
            pageIndex: probe.index, fatal: true));
        badIndexes.add(probe.index);
        continue;
      }
      final w = sniff.width;
      final h = sniff.height;
      if (w != null && h != null) {
        if (w < 16 || h < 16) {
          issues.add(ValidationIssue('tracker', 'Image minuscule (${w}x$h).',
              pageIndex: probe.index, fatal: true));
          badIndexes.add(probe.index);
          continue;
        }
        // Webtoon policies lower minHeight for thin slices; width still counts.
        final tooSmall = w < policy.minWidth || h < policy.minHeight;
        if (tooSmall) {
          smallPages++;
          final tolerated = smallPages <= policy.allowSmallPages;
          issues.add(ValidationIssue('small',
              'Image trop petite pour une planche (${w}x$h).',
              pageIndex: probe.index, fatal: !tolerated));
          if (!tolerated) {
            badIndexes.add(probe.index);
            continue;
          }
        }
      }
      final hash = probe.contentHash;
      if (hash != null) {
        final first = hashes[hash];
        if (first != null) {
          // Only full-file hashes prove a repeated image; identical
          // beginnings of two truncated downloads are just a warning.
          final proven = first.$2 && probe.complete;
          issues.add(ValidationIssue('same_image',
              'Image identique à la page ${first.$1 + 1}.', pageIndex: probe.index,
              fatal: proven));
          if (proven) {
            badIndexes.add(probe.index);
            continue;
          }
        } else {
          hashes[hash] = (probe.index, probe.complete);
        }
      }
    }

    // Pages read in a site's scripts may start or end with a small site
    // image (icon, avatar 128×128, « end » badge). When the ONLY problems
    // are such small images at the very start / end, they are removed and
    // the chapter keeps its real pages (instead of « incomplete »).
    if (transport == 'html-script' && badIndexes.isNotEmpty && access == AccessKind.open) {
      final smallOnly = badIndexes.every((i) => issues.any((x) =>
          x.pageIndex == i && x.fatal && (x.code == 'small' || x.code == 'tracker')));
      final sorted = badIndexes.toList()..sort();
      var edge = true;
      var head = 0;
      while (head < sorted.length && sorted[head] == head) {
        head++;
      }
      for (var k = head; k < sorted.length; k++) {
        if (sorted[k] != pages.length - (sorted.length - k)) edge = false;
      }
      if (smallOnly && edge && pages.length - badIndexes.length >= 3) {
        final kept = [
          for (var i = 0; i < pages.length; i++) if (!badIndexes.contains(i)) pages[i],
        ];
        return evaluate(kept,
            announcedTotal: announcedTotal == null ? null : kept.length,
            probes: [
              for (final pr in probes)
                if (!badIndexes.contains(pr.index))
                  pr.withIndex(pr.index - sorted.where((b) => b < pr.index).length),
            ],
            policy: policy,
            offline: offline,
            transport: 'html-script-trimmed',
            elapsed: elapsed,
            imageHeaders: imageHeaders);
      }
    }
    final validCount = pages.length - badIndexes.length;
    final fatalGlobal = issues.any((i) => i.fatal && i.pageIndex == null);
    final PageCompleteness completeness;
    if (access != AccessKind.open && access != AccessKind.rateLimited &&
        validCount <= (pages.length / 2).floor()) {
      completeness = PageCompleteness.restricted;
    } else if (fatalGlobal || validCount <= 0) {
      completeness = PageCompleteness.invalid;
    } else if (announcedTotal != null && announcedTotal > 0) {
      completeness = validCount >= announcedTotal && badIndexes.isEmpty
          ? PageCompleteness.complete
          : PageCompleteness.partial;
    } else if (badIndexes.isNotEmpty) {
      completeness = PageCompleteness.partial;
    } else if (pages.length == 1 && probes.isEmpty) {
      // Never invent a "1/1" chapter from one unverified image.
      completeness = PageCompleteness.invalid;
      issues.add(const ValidationIssue('single_unverified',
          'Une seule image non vérifiée : chapitre non confirmé.', fatal: true));
    } else {
      completeness = PageCompleteness.unconfirmed;
    }
    return ChapterPages(
      pages: pages,
      completeness: completeness,
      announcedTotal: announcedTotal,
      validCount: validCount < 0 ? 0 : validCount,
      access: access,
      issues: List.unmodifiable(issues),
      transport: transport,
      elapsed: elapsed,
      imageHeaders: imageHeaders,
    );
  }

  /// Indexes worth probing: first page always (fast first display), last
  /// page (truncation), and one middle page on long chapters.
  static List<int> probeSample(int count) {
    if (count <= 0) return const [];
    final out = <int>{0, count - 1};
    if (count >= 8) out.add(count ~/ 2);
    return out.toList()..sort();
  }

  static bool _hostMatches(String host, String allowed) {
    final h = host.toLowerCase();
    final a = allowed.toLowerCase();
    return h == a || h.endsWith('.$a');
  }

  static bool _isLocalHost(String hostname) {
    final host = hostname.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || host.endsWith('.internal') ||
        host.contains(':')) {
      return true;
    }
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (v4 == null) return false;
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    return a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) ||
        (a == 100 && b >= 64 && b <= 127) || a >= 224;
  }
}
