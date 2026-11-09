# Pazulu Reader 0.4.1 — une seule fenêtre

## Objectif

La V0.4.0 ouvrait certains chapitres officiels via Edge `--app=...` dans une fenêtre distincte. Ce comportement est retiré dans cette correction. L'utilisateur reste dans **la fenêtre de Pazulu Reader**.

## Intégration

- Windows : `webview_flutter_windows` 1.3.1, rendu WebView2 en **texture Flutter**. Aucun lancement d'`msedge.exe`, pas de fenêtre de lecture secondaire.
- Android : le lecteur `webview_flutter` existant est conservé.
- Sources du catalogue et liens ajoutés sur les fiches : une nouvelle **page interne de Pazulu Reader** affiche le site. La navigation « retour » revient à la fiche ou à la liste des sources, sans nouvelle fenêtre du système.
- Chapitres MangaDex accessibles par des images : le lecteur maison existant est inchangé.
- Sites tiers : leur site est rendu tel quel, avec leurs connexions, règles et éventuels abonnements. Une vue WebView n'autorise ni extraction automatique des pages ni téléchargement CBZ par elle-même.

## Contraintes et précautions

- Windows 10 1809+ ou 11 avec **WebView2 Runtime**. Il est généralement inclus dans Windows 11.
- Développement Windows : **Flutter 3.44+**, Dart 3.12+, Visual Studio 2022 avec « Développement Desktop en C++ » et Windows SDK.
- Aucun contournement des DRM et des restrictions des sites.
- Les popups demandant une nouvelle fenêtre sont refusées pour respecter le principe « une seule fenêtre ». Sur certains sites, une connexion ou une action dépendant d'une popup pourra échouer.
- Certaines pages peuvent refuser les navigateurs intégrés, ou exiger des fonctions non prises en charge. Les cas doivent être testés site par site.
- Les versions antérieures de WebView Windows avaient planté sous Flutter 3.47 sur le PC de test. Cette version utilise une **implémentation différente et entretenue**, mais **son fonctionnement et son absence de plantage ne sont pas vérifiés sans exécuter l'application sur Windows**.

## Test Windows

1. Sauvegarder la bibliothèque depuis Réglages → Sauvegarde (facultatif mais recommandé avant une mise à jour).
2. Extraire l'archive dans un **nouveau dossier** (ne pas mélanger les sources avec celles de la V0.4.0).
3. Dans PowerShell, depuis le dossier contenant `Compiler.cmd`, lancer :

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\build.ps1 -SkipAndroid
   ```

4. Quand la compilation est terminée sans erreur, ouvrir `dist\PazuluReader-0.4.1-windows\pazulu_reader.exe`.
5. Depuis une fiche, ouvrir un chapitre officiel (exemple « Solo Leveling » → lien Webnovel). **L'image du site doit apparaître dans la grande zone de Pazulu Reader, pas dans une seconde fenêtre.**
6. Depuis Découvrir → Sources, ouvrir un site de la liste ; utiliser la flèche Retour pour revenir à l'application.
7. Vérifier que la bibliothèque, les thèmes, les animations et les chapitres CBZ fonctionnent toujours.
8. Si compilation ou test échoue, envoyer `dist\build-log.txt`. Si l'application s'arrête, exécuter `Diagnostic.cmd` puis envoyer `dist\diagnostic.txt`.

**Statut** : modification du code et contrôles statiques effectués dans l'environnement de création. Compilation Windows/Android et test graphique non réalisés ici faute de SDK et de Windows.
