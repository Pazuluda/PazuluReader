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
