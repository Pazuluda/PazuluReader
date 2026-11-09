# Pazulu Reader V0.4.2 - lecture integree Windows (correctif crash)

## Probleme observe en V0.4.1

En ouvrant un chapitre officiel (Webnovel, etc.) ou une source dans la vue interne, l'application Windows se ferme brutalement. Le composant V0.4.1 utilise une texture Flutter externe pour afficher WebView2. Un crash natif de Flutter / C++ peut arreter tout le processus sans passer par les gestionnaires d'exceptions Dart.

Ce n'est PAS un probleme d'ouverture de deux fenetres. La seconde fenetre Edge des versions anterieures evitait simplement la creation d'une WebView2 native dans le processus Flutter.

## Modification de la V0.4.2

- Retrait du paquet `webview_flutter_windows` et de sa capture graphique en texture.
- Ajout de `webview_win_floating` 3.0.3 : le navigateur WebView2 utilise un HWND enfant de la fenetre Pazulu (et non une application Edge distincte).
- Le profil WebView2 et ses cookies sont enregistres sous le dossier de donnees de Pazulu dans AppData, pas dans le repertoire d'installation de l'EXE.
- Les URL dangereuses / non HTTPS restent bloquees. Les demandes de navigation secondaire / nouvelles fenetres sont refusees par le delegue de navigation. Certains liens de connexion ou lecteurs tiers peuvent s'en trouver limites.
- Une garde anti-crash (`webview-v042-active.flag`) est creee avant l'initialisation native. En cas de crash Windows, le marqueur persiste et la tentative suivante affiche un message au lieu de replanter immediatement. Cliquer sur « Reessayer dans Pazulu » pour retenter explicitement. Ce fichier n'est pas une preuve de crash : une fermeture forcee pendant la lecture peut aussi le laisser en place.
- Quand la vue est fermee proprement, le marqueur est supprime.
- La WebView native se superpose uniquement a son rectangle. Le lecteur officiel reserve deja une marge en haut et en bas ; les commandes du lecteur doivent rester en dehors de la surface native. Il ne faut pas placer de dialogue Flutter par-dessus ce controle : la couche native passerait devant.
- Aucun logiciel ni extension Firefox/Chrome requis ; le WebView2 Runtime de Microsoft est necessaire.

## Points inchanges

- `lib/design/theme.dart`, `lib/ui/shell.dart`, `lib/ui/widgets/motion.dart`, `lib/ui/widgets/common.dart` et `lib/ui/reader_page.dart` sont IDENTIQUES a la V0.4.1.
- Mode nuit, six palettes, toutes les animations existantes, lecteur CBZ/MangaDex, favoris, suivi de lecture, detections et sauvegardes : pas de refonte.
- Android : moteur web `webview_flutter` existant conserve.
- Les autres sites restent consultables dans une vue interne, mais ne sont pas devenus des connecteurs de chapitres autorises.

## Protocole de test Windows

1. Faire une sauvegarde `.pazulu` depuis Reglages pour securiser la bibliotheque.
2. Extraire l'archive **dans un nouveau dossier** : ne pas ecraser les fichiers `windows/`, `.dart_tool/` ou `.flutter-plugins-dependencies` de la version precedente.
3. Double-cliquer `Compiler-Windows.cmd` (Windows uniquement, recommande), `Compiler.cmd` (Windows + Android) ou lancer `powershell -ExecutionPolicy Bypass -File .\tools\build.ps1 -SkipAndroid`.
4. Ouvrir `dist\PazuluReader-0.4.2-windows\pazulu_reader.exe` (le dossier entier doit etre conserve).
5. Tester la recherche MangaDex et une lecture CBZ ordinaire.
6. Ouvrir une source via « Voir mes 15 sources ». Verifier que le site reste dans la fenetre Pazulu Reader, que la barre Retour fonctionne et qu'aucune seconde fenetre Edge n'apparait.
7. Ouvrir le chapitre de Solo Leveling / Webnovel qui faisait planter la V0.4.1, puis revenir et reouvrir la page. Verifier que le lecteur se ferme proprement, sans blocage.
8. Fermer Pazulu puis relancer. Verifier que la sauvegarde et la progression restent intactes.
9. Si la compilation echoue, transmettre `dist\build-log.txt` ; si Windows ferme encore l'app, lancer `Diagnostic.cmd` et transmettre `dist\diagnostic.txt`. Les evts 1000/1026 donnent habituellement le module fautif.

## Limites / validation

Le rendu HWND natif evite le chemin d'execution qui causait potentiellement les crashs de capture GPU de la V0.4.1, mais **il n'est pas possible de garantir une absence de crash natif sans executer le programme sur le PC concerne**. Une page qui exige une popup ou refuse les navigateurs integres peut rester incompatible. Ce correctif ne contourne pas les DRM ni les regles des sources.

## References

- Flutter issue #180560 - crashes natifs de Flutter Windows utilisant WebView / textures : https://github.com/flutter/flutter/issues/180560
- Flutter issue #191478 - regression Flutter 3.47 sur la gestion de views Windows : https://github.com/flutter/flutter/issues/191478
- webview_win_floating 3.0.3 : https://pub.dev/packages/webview_win_floating
