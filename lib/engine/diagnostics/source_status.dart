import '../availability.dart';

/// Audited capability of a source/domain. `fullReader` is only granted after
/// a chapter was actually resolved AND its pages validated.
enum SourceStatus {
  fullReader,
  partialReader,
  metadataOnly,
  externalOnly,
  loginRequired,
  subscriptionRequired,
  blocked,
  broken,
  unverified,
}

extension SourceStatusLabel on SourceStatus {
  String get code => switch (this) {
        SourceStatus.fullReader => 'FULL_READER',
        SourceStatus.partialReader => 'PARTIAL_READER',
        SourceStatus.metadataOnly => 'METADATA_ONLY',
        SourceStatus.externalOnly => 'EXTERNAL_ONLY',
        SourceStatus.loginRequired => 'LOGIN_REQUIRED',
        SourceStatus.subscriptionRequired => 'SUBSCRIPTION_REQUIRED',
        SourceStatus.blocked => 'BLOCKED',
        SourceStatus.broken => 'BROKEN',
        SourceStatus.unverified => 'UNVERIFIED',
      };

  String get label => switch (this) {
        SourceStatus.fullReader => 'Lecture complète vérifiée',
        SourceStatus.partialReader => 'Lecture partielle',
        SourceStatus.metadataOnly => 'Fiches uniquement',
        SourceStatus.externalOnly => 'Liens externes uniquement',
        SourceStatus.loginRequired => 'Connexion requise',
        SourceStatus.subscriptionRequired => 'Abonnement requis',
        SourceStatus.blocked => 'Bloquée',
        SourceStatus.broken => 'En panne',
        SourceStatus.unverified => 'Non vérifiée',
      };

  bool get readable => this == SourceStatus.fullReader || this == SourceStatus.partialReader;

  static SourceStatus parse(String? code) => SourceStatus.values.firstWhere(
      (s) => s.code == code, orElse: () => SourceStatus.unverified);

  static SourceStatus fromAccess(AccessKind kind) => switch (kind) {
        AccessKind.subscriptionRequired => SourceStatus.subscriptionRequired,
        AccessKind.loginRequired => SourceStatus.loginRequired,
        AccessKind.botChallenge || AccessKind.rateLimited ||
        AccessKind.regionLocked || AccessKind.ageVerification ||
        AccessKind.cookieConsent => SourceStatus.blocked,
        AccessKind.removed || AccessKind.maintenance ||
        AccessKind.unknownRestriction => SourceStatus.broken,
        AccessKind.open => SourceStatus.unverified,
      };
}
