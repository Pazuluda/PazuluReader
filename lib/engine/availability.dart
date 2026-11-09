import '../core/models.dart';
import '../core/source.dart';

/// Why a chapter cannot be shown as manga pages. Separate from metadata:
/// a chapter listed by a source is NOT automatically readable.
enum AccessKind {
  /// Nothing suggests a restriction.
  open,
  subscriptionRequired,
  loginRequired,
  ageVerification,
  cookieConsent,
  botChallenge,
  regionLocked,
  removed,
  rateLimited,
  maintenance,
  unknownRestriction,
}

extension AccessKindLabel on AccessKind {
  String get label => switch (this) {
        AccessKind.open => 'Accessible',
        AccessKind.subscriptionRequired => 'Abonnement ou achat requis',
        AccessKind.loginRequired => 'Connexion requise',
        AccessKind.ageVerification => 'Vérification d\'âge demandée par le site',
        AccessKind.cookieConsent => 'Écran de consentement aux cookies',
        AccessKind.botChallenge => 'Vérification anti-robot (CAPTCHA)',
        AccessKind.regionLocked => 'Indisponible dans cette région',
        AccessKind.removed => 'Chapitre retiré ou introuvable',
        AccessKind.rateLimited => 'Trop de requêtes (HTTP 429)',
        AccessKind.maintenance => 'Site en maintenance',
        AccessKind.unknownRestriction => 'Accès restreint',
      };

  /// Restrictions Pazulu must report rather than work around.
  bool get isRestriction => this != AccessKind.open;

  /// A later retry can reasonably succeed without user action.
  bool get isTransient => this == AccessKind.rateLimited ||
      this == AccessKind.maintenance || this == AccessKind.botChallenge;
}

/// Completeness of a resolved page list.
enum PageCompleteness {
  /// Announced total known and every page validated.
  complete,

  /// No announced total: pages look valid but completeness is unproven.
  unconfirmed,

  /// Fewer valid pages than announced.
  partial,

  /// The "pages" are an error, a paywall, a login or an age gate.
  restricted,

  /// Nothing usable (empty, HTML disguised as images, logos…).
  invalid,
}

extension PageCompletenessLabel on PageCompleteness {
  String get label => switch (this) {
        PageCompleteness.complete => 'Complet',
        PageCompleteness.unconfirmed => 'Complétude non confirmée',
        PageCompleteness.partial => 'Incomplet',
        PageCompleteness.restricted => 'Accès restreint',
        PageCompleteness.invalid => 'Pages invalides',
      };

  /// Pages can be displayed to the reader.
  bool get readable => this == PageCompleteness.complete ||
      this == PageCompleteness.unconfirmed;
}

/// Result of checking whether a chapter can be read, WITHOUT returning pages.
class ChapterAvailability {
  const ChapterAvailability({
    required this.access,
    this.detail,
    this.httpStatus,
    this.retryAfter,
    this.checkedAt,
  });

  const ChapterAvailability.open()
      : access = AccessKind.open,
        detail = null,
        httpStatus = null,
        retryAfter = null,
        checkedAt = null;

  final AccessKind access;
  final String? detail;
  final int? httpStatus;
  final Duration? retryAfter;
  final DateTime? checkedAt;

  bool get isOpen => access == AccessKind.open;
}

/// A validation finding, kept for diagnostics and the reader status panel.
class ValidationIssue {
  const ValidationIssue(this.code, this.message, {this.pageIndex, this.fatal = false});

  final String code;
  final String message;
  final int? pageIndex;
  final bool fatal;

  @override
  String toString() => pageIndex == null ? message : 'Page ${pageIndex! + 1} : $message';
}

/// Resolved pages + the validation verdict. Separate from availability.
class ChapterPages {
  const ChapterPages({
    required this.pages,
    required this.completeness,
    this.announcedTotal,
    this.validCount = 0,
    this.access = AccessKind.open,
    this.issues = const [],
    this.transport = 'api',
    this.elapsed,
    this.imageHeaders = const {},
  });

  final List<PageRef> pages;

  /// Headers needed to display these images (e.g. Referer = chapter URL).
  final Map<String, String> imageHeaders;
  final PageCompleteness completeness;
  final int? announcedTotal;
  final int validCount;
  final AccessKind access;
  final List<ValidationIssue> issues;

  /// api / html / browser / offline.
  final String transport;
  final Duration? elapsed;

  bool get readable => completeness.readable && pages.isNotEmpty;

  String get summary {
    final total = announcedTotal;
    final count = total == null ? '${pages.length} pages' : '$validCount/$total pages';
    return '${completeness.label} · $count';
  }
}

/// A chapter refused for an access reason. Never displayed as a page.
class ChapterRestrictedException extends SourceException {
  const ChapterRestrictedException(super.message,
      {required this.kind, super.statusCode, this.retryAfter});

  final AccessKind kind;
  final Duration? retryAfter;
}

/// The page list was obtained but failed validation (partial, invalid…).
class ChapterValidationException extends SourceException {
  const ChapterValidationException(super.message, {required this.result});

  final ChapterPages result;
}
