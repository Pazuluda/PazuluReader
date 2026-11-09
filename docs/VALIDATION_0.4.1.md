# Validation de la V0.4.1

## Verifie dans cet environnement

- Presence et structure des sources Dart de la V0.4.0.
- Suppression du lancement d'Edge en mode application pour les chapitres officiels.
- Plus d'appel `LaunchMode.externalApplication` dans le lecteur, les sources ou la fiche.
- Nouvelle vue WebView2 en texture Flutter (Windows), retour a l'interface Pazulu.
- 15 sites conserves dans le catalogue avec controle des liens HTTPS.
- Versions coherentes : `appVersion`, `pubspec.yaml`, `tools/build.ps1`.
- Fichiers de DA compares par SHA-256 avec la V0.4.0, identiques : `design/theme.dart`, `ui/shell.dart`, `ui/widgets/motion.dart`, `ui/widgets/common.dart`, pages d'accueil, decouverte, bibliotheque, reglage ; autres fichiers de donnees et de lecteur CBZ inchanges.

## NON verifie ici

- Compilation Flutter/Windows : SDK Flutter absent du conteneur.
- Compilation Flutter/Android : SDK Flutter/Android absent du conteneur.
- Execution d'une WebView2 sur Windows, connexion Webnovel, rendu, navigation, focus clavier et absence de crash.
- `flutter analyze` et `flutter test` : a executer sur Windows via `tools/build.ps1`.

**La release est une correction de code a tester, pas un EXE compile ou une garantie de lecture sur tous les sites.**
