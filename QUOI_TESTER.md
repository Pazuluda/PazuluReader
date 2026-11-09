# Pazulu Reader V0.5.4 — Vérification sur Windows

1. Fermer Pazulu Reader, puis lancer `Compiler-Windows.cmd` depuis le nouveau dossier.
2. Vérifier la réussite de `flutter analyze`, `flutter test` et `flutter build windows --release` ; les résultats ne peuvent pas être certifiés dans cet environnement sans Flutter.
3. Sur Solo Leveling, ouvrir le chapitre 198 : le chargement `8/13` est une progression, **pas** la fin du chapitre. Le lecteur doit attendre la totalité des pages annoncées.
4. Tester une édition MangaDex et une lecture Pepper&Carrot ; vérifier l'affichage natif des images et la progression.
5. Pour une œuvre ayant **au moins deux lecteurs effectivement disponibles**, désactiver la connexion au premier lecteur ou provoquer un échec contrôlé ; vérifier l'essai automatique du Lecteur 2 sans voir le site tiers.
6. Tester les pastilles Lecteur 1 / 2 / 3 et les touches 1, 2, 3 (seules les versions du chapitre existantes sont proposées).
7. Vérifier qu'une image invalide provoque un changement de lecteur (s'il existe), sans validation d'un chapitre incomplet.
8. Vérifier qu'un site simplement présent dans le catalogue ne devient pas un faux lecteur : un connecteur réellement installé est nécessaire.
9. Vérifier que la bibliothèque, les deux profils et les chapitres CBZ restent intacts.

Test ciblé : `flutter test test/reader_failover_v054_test.dart`
Simulation JS : `node tools/test_pagination_mock.js`.
Envoyer `dist\build-log.txt` si une erreur de compilation ou de test persiste.
