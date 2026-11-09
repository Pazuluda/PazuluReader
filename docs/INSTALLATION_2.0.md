# Installation et compilation — Pazulu Reader 2.0.0 (Windows)

## Prérequis (inchangés depuis la V0.5.4)
- Windows 10/11 64 bits, Flutter stable (Dart ≥ 3.6) — votre installation `%USERPROFILE%\dev\flutter` est détectée automatiquement par le script.
- Visual Studio 2022 « Développement Desktop C++ », runtime WebView2 (présent sur Windows 11).
- Facultatif : Inno Setup 6 pour l'installateur `.exe`.

## Compiler
1. **Fermez Pazulu Reader** (le packaging refuse d'écraser un EXE ouvert).
2. Décompressez le code source dans un dossier sans accents, par ex. `C:\dev\pazulu_reader`.
3. Double-cliquez `Compiler-Windows.cmd`. Étapes : `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build windows --release` → archive portable `dist\PazuluReader-2.0.0-windows.zip` (+ installateur si Inno Setup est présent).
4. Le journal complet est dans `dist\build-log.txt`. En cas d'échec, envoyez-le : il ne contient pas vos données personnelles.

## Données et migration
- Vos bibliothèques, profils, favoris, historiques et progressions restent dans le même dossier (`%APPDATA%\com.pazulu\pazulu_reader` ou équivalent) et le même format JSON. Les nouveaux réglages ont des valeurs par défaut ; aucun champ existant n'est modifié. Une sauvegarde automatique quotidienne `.pazulu` est conservée (7 jours).
- Nouveaux fichiers créés à côté : `extensions\registry.json`, `extensions\<id>\<version>.json`, `engine\connector-health.json`. Les supprimer réinitialise seulement les extensions et statistiques.
- Retour à la V0.5.4 possible : elle ignore les nouveaux champs.
- Cas limite connu : un chapitre numéroté « 115.10 » chez MangaDex était auparavant enregistré comme « 115.1 » ; il peut réapparaître « non lu » une fois.

## Nouveautés visibles
- Lecteur : barre « Lecteur 1 / 2 / 3 » (source, langue, état vérifié), « Rechercher une autre source », « Par défaut », panneau d'étapes pendant la recherche du chapitre, double page (D), ajustement page/largeur/hauteur (W), sens de lecture mémorisé par œuvre (M).
- Paramètres → **Moteur Pazulu** : basculement automatique, secours dans une autre langue, **Extensions**, **Diagnostic des sources**.
