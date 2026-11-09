import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/ui/splash/splash_screen.dart';

void main() {
  test('segments : seulement les étapes réellement terminées', () {
    expect(StartupProgress.completedBefore('Ouverture du profil…'), 0);
    expect(StartupProgress.completedBefore('Chargement des sources…'), 1);
    expect(StartupProgress.completedBefore('Préparation du moteur de lecture…'), 2);
    expect(StartupProgress.completedBefore('Chargement de la bibliothèque…'), 3);
    expect(StartupProgress.completedBefore('Chapitres de la bibliothèque · 3/12'), 4);
    expect(StartupProgress.completedBefore('Catalogues des sites · 2/9 · x'), 4);
    expect(StartupProgress.completedBefore('Démarrage…'), isNull);
  });

  test('la barre n’avance jamais à reculons', () {
    final p = StartupProgress();
    p.report('Chargement de la bibliothèque…');
    expect(p.steps.value, 3);
    p.report('Chargement des sources…');
    expect(p.steps.value, 3);
    p.reached(5);
    expect(p.steps.value, 5);
    expect(p.label.value, 'Chargement des sources…');
  });
}
