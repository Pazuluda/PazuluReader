import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/french_text.dart';
import 'package:pazulu_reader/core/models.dart';

void main() {
  test('reconnaît un résumé en français', () {
    expect(FrenchText.looksFrench(
        'Dans un monde où des portails relient la Terre à des donjons, Sung Jin-Woo est le chasseur '
        'le plus faible de tous. Il survit de justesse à un raid et reçoit un pouvoir unique.'), isTrue);
    expect(FrenchText.looksFrench(
        'In a world where portals link Earth to dungeons, Sung Jin-Woo is the weakest hunter of all. '
        'He barely survives a raid and receives a unique power.'), isFalse);
    expect(FrenchText.looksFrench(''), isFalse);
  });

  test('réglage : activé par défaut, enregistré et relu', () {
    expect(Settings.fromJson(const {}).frenchSummaries, isTrue);
    final s = Settings()..frenchSummaries = false;
    expect(Settings.fromJson(s.toJson()).frenchSummaries, isFalse);
  });

  test('texte publicitaire de site : pas un résumé', () {
    expect(SiteBlurb.looksLike(
        'Lisez Swordmaster’s Youngest Son en français gratuitement sur Scan Reader. '
        'Tous les chapitres disponibles en lecture en ligne.', siteName: 'scanreader.net'), isTrue);
    expect(SiteBlurb.looksLike('Lire Solo Leveling VF scan sur mangasite.fr'), isTrue);
    expect(SiteBlurb.looksLike('Read Omniscient Reader online free, latest chapters.'), isTrue);
    // Un vrai résumé, même s'il contient « lire » une fois.
    expect(SiteBlurb.looksLike(
        'Jin Runcandel, le fils cadet du clan d\'épéistes le plus célèbre du continent, a été chassé de sa '
        'famille. Revenu dans le passé avec ses souvenirs, il décide de tout reprendre et de devenir '
        'le plus fort, quitte à apprendre à lire les intentions de ses frères.'), isFalse);
  });
}
