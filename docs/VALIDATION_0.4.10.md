# Rapport de validation V0.4.10

## Controle real effectue ici

- Les fichiers Flutter et les scripts de compilation sont presentes.
- Verification du nom du package, de la version de `pubspec.yaml`, du script `tools/build.ps1` et de `appVersion`.
- Verification des nouveaux points d'entree de lecture, de cache et des tests.
- Comparaison octet par octet de 11 fichiers de DA, navigation et navigateur de sources avec le projet V0.4.9 corrige : aucune modification.
- Archive ZIP relue apres creation et controle CRC de tous les fichiers.

## Non realise dans cet environnement

- `flutter analyze`, `flutter test`, `flutter build windows` et `flutter build apk` non executes : ni Flutter ni Dart SDK disponibles.
- Pas de test de connexion en direct aux serveurs des sources, donc succes des requetes a confirmer sur le PC Windows.
- Pas de certification du fonctionnement de tous les sites du catalogue. Les 13 profils precedents restent en place.

## Scenarios Flutter inclus dans `test/`

- Les metadata sont interrogees sans recuperer de pages de chapitre.
- Lecture d'un chapitre compatible -> CBZ avec image authentique -> relecture locale sans nouvel appel source.
- Page HTML repondant HTTP 200 rejete comme image (captcha / challenge).
- Reglage cache automatique persiste et migration des anciens parametres.
- Index FR/EN Pepper&Carrot, URL de chaque page creee sur le clic en lecture.
- Fusion conservative de titres identiques venant de connecteurs differents.

Pour valider effectivement : extraire les sources puis lancer `Compiler-Windows.cmd` sur le PC utilisateur et transmettre `dist/build-log.txt` si besoin.
