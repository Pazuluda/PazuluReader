import '../availability.dart';

/// Recognises pages that are NOT manga pages: paywalls, "no longer free",
/// login walls, age gates, cookie walls, bot challenges, 404 / removed pages.
///
/// Detection only: Pazulu reports the restriction and looks for another real
/// source. It never clicks through, never forges a consent/age answer and
/// never attempts to solve a challenge.
class AccessDetector {
  const AccessDetector._();

  static final List<(AccessKind, RegExp)> _rules = [
    (AccessKind.botChallenge, RegExp(
        r"just a moment|checking your browser|attention required|cf-chl|"
        r"verify you are human|v[eé]rifiez que vous [eê]tes humain|"
        r"captcha|ddos-guard|are you a robot|enable javascript and cookies to continue")),
    (AccessKind.subscriptionRequired, RegExp(
        r"subscription required|subscribe to (?:read|continue|unlock)|"
        r"no longer (?:available )?(?:for )?free|is no longer free|not free anymore|"
        r"n'est plus gratuit|n.est plus disponible gratuitement|plus gratuit|"
        r"r[eé]serv[eé] aux abonn[eé]s|abonnez-vous pour (?:lire|continuer)|"
        r"abonnement (?:requis|n[eé]cessaire)|"
        r"unlock (?:this )?chapter|buy (?:this )?chapter|purchase (?:this )?chapter|"
        r"acheter (?:ce )?chapitre|d[eé]bloquer (?:ce )?chapitre|"
        r"use (?:\d+ )?(?:coins?|points?|tickets?) to read|"
        r"premium (?:members|chapter|only)|members only|"
        r"free (?:trial|period) (?:has )?ended|limited[- ]time free (?:has )?ended|"
        r"購入|有料")),
    (AccessKind.loginRequired, RegExp(
        r"(?:log ?in|sign ?in) (?:to|required to) (?:read|continue|view)|"
        r"please (?:log ?in|sign ?in)|login required|you must be logged in|"
        r"connectez-vous pour (?:lire|continuer)|connexion requise|"
        r"vous devez [eê]tre connect[eé]")),
    (AccessKind.ageVerification, RegExp(
        r"age verification|verify your age|are you (?:over )?18|"
        r"you must be (?:over |at least )?18|18\+ only|mature content warning|"
        r"v[eé]rification de l.[aâ]ge|[eê]tes-vous majeur|avez-vous 18 ans|"
        r"18 ans ou plus|contenu r[eé]serv[eé] aux adultes|"
        r"年齢確認")),
    (AccessKind.regionLocked, RegExp(
        r"not available in your (?:country|region)|"
        r"unavailable in your (?:country|region)|"
        r"pas disponible dans votre (?:pays|r[eé]gion)|geo-?blocked")),
    (AccessKind.maintenance, RegExp(
        r"under maintenance|we are upgrading|we.re upgrading our website|"
        r"en maintenance|site en travaux")),
    (AccessKind.removed, RegExp(
        r"chapter (?:not found|has been removed|was removed|unavailable)|"
        r"chapitre (?:introuvable|supprim[eé]|retir[eé]|indisponible)|"
        r"404 (?:not found|error)|page not found|page introuvable|"
        r"this content has been removed|dmca|takedown|"
        r"oops! that page can.t be found|nothing found")),
    (AccessKind.cookieConsent, RegExp(
        r"accept (?:all )?cookies|we use cookies|accepter (?:tous )?les cookies|"
        r"g[eé]rer (?:mes|les) cookies|consent to (?:the use of )?cookies")),
  ];

  /// Classifies visible text (HTML body text, WebView innerText or a short
  /// text/html body returned instead of an image).
  ///
  /// [imageCount] is the number of plausible page images found next to the
  /// text. A real chapter page with a cookie banner is still a chapter, so
  /// weak signals (cookies, 404 words in a footer) only count when nothing
  /// readable is present.
  static AccessKind classifyText(String text, {int imageCount = 0}) {
    final lower = text.toLowerCase();
    if (lower.trim().isEmpty) return AccessKind.open;
    for (final (kind, pattern) in _rules) {
      if (!pattern.hasMatch(lower)) continue;
      switch (kind) {
        case AccessKind.cookieConsent:
        case AccessKind.removed:
        case AccessKind.ageVerification:
          // Sites often show a cookie bar, an "18+" disclaimer or a generic
          // "nothing found" widget around real pages.
          if (imageCount >= 2) continue;
          return kind;
        case AccessKind.subscriptionRequired:
        case AccessKind.loginRequired:
          // A paywall teaser can include 1-3 preview images.
          if (imageCount >= 6) continue;
          return kind;
        default:
          return kind;
      }
    }
    return AccessKind.open;
  }

  /// Maps an HTTP status to an access state; 2xx returns [AccessKind.open].
  static AccessKind classifyStatus(int status) {
    if (status >= 200 && status < 300) return AccessKind.open;
    return switch (status) {
      401 => AccessKind.loginRequired,
      402 => AccessKind.subscriptionRequired,
      403 => AccessKind.botChallenge,
      404 || 410 => AccessKind.removed,
      429 => AccessKind.rateLimited,
      451 => AccessKind.regionLocked,
      503 => AccessKind.maintenance,
      _ => AccessKind.unknownRestriction,
    };
  }

  /// Visible text of an HTML document without scripts/styles, bounded.
  static String visibleTextOf(String html, {int max = 20000}) {
    var text = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#039;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (text.length > max) text = text.substring(0, max);
    return text;
  }
}
