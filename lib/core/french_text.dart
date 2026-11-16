/// Reconnaît un texte en français (résumés) sans service externe : mots
/// courants du français contre ceux de l'anglais.
class FrenchText {
  FrenchText._();

  static const _fr = {
    'le', 'la', 'les', 'des', 'une', 'un', 'est', 'et', 'dans', 'qui', 'pour', 'sur', 'avec',
    'il', 'elle', 'son', 'sa', 'ses', 'du', 'au', 'aux', 'que', 'pas', 'mais', 'leur', 'ce',
    'cette', 'ne', 'se', 'lui', 'être', 'été', 'où', 'après', 'monde', 'jeune',
  };
  static const _en = {
    'the', 'and', 'of', 'to', 'is', 'in', 'his', 'her', 'with', 'he', 'she', 'that', 'for',
    'on', 'was', 'but', 'from', 'by', 'this', 'their', 'who', 'an', 'as', 'be', 'world', 'young',
  };
  static final RegExp _words = RegExp(r"[a-zàâäéèêëîïôöùûüç]+");

  static bool looksFrench(String text) {
    var fr = 0, en = 0;
    for (final m in _words.allMatches(text.toLowerCase())) {
      final w = m.group(0)!;
      if (_fr.contains(w)) fr++;
      if (_en.contains(w)) en++;
    }
    return fr >= 3 && fr > en * 1.5;
  }
}

/// Texte publicitaire d'un site (« Lisez X en français gratuitement sur
/// Scan Reader. Tous les chapitres disponibles… ») et non un résumé de
/// l'histoire.
class SiteBlurb {
  SiteBlurb._();

  static final RegExp _domain = RegExp(r'\b[a-z0-9-]+\.(com|net|org|fr|io|co|me|xyz|to|cc|gg|site|online|info)\b',
      caseSensitive: false);
  static final List<RegExp> _seo = [
    RegExp(r'\b(lire|lisez|read|regarder)\b', caseSensitive: false),
    RegExp(r'\bgratuit(e|ement)?\b|\bfree\b|\bfreely\b', caseSensitive: false),
    RegExp(r'\ben ligne\b|\bonline\b', caseSensitive: false),
    RegExp(r'\b(scans?|vf|vostfr|raw)\b', caseSensitive: false),
    RegExp(r'tous les chapitres|all chapters|derniers? chapitres?|latest chapters?|chapitres? disponibles?',
        caseSensitive: false),
    RegExp(r'\b(sur|on) (notre|our) site\b|\bmeilleur site\b|\bbest site\b', caseSensitive: false),
    RegExp(r'\bmanga en fran[cç]ais\b|\bwebtoon en fran[cç]ais\b|\ben fran[cç]ais sur\b', caseSensitive: false),
    RegExp(r'\bt[ée]l[ée]charg', caseSensitive: false),
  ];

  /// true quand [text] parle du site (où lire, gratuit, chapitres
  /// disponibles…) au lieu de raconter l'histoire. [siteName] : le nom du
  /// site, qui ne figure jamais dans un vrai résumé.
  static bool looksLike(String text, {String? siteName}) {
    final t = text.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (siteName != null && siteName.length >= 4 && lower.contains(siteName.toLowerCase())) return true;
    var hits = 0;
    for (final r in _seo) {
      if (r.hasMatch(t)) hits++;
    }
    if (_domain.hasMatch(t)) hits += 2;
    // Un vrai résumé long peut contenir un de ces mots ; une phrase de
    // site en a plusieurs et reste courte.
    return t.length < 400 ? hits >= 2 : hits >= 4;
  }
}
