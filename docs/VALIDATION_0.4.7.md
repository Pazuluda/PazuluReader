# V0.4.7 — verification des sorties, tests Windows

## Ce qui a reellement change

1. La verification des nouveautes produit un bilan **par oeuvre, connecteur et langue**.
   Un site accessible en HTTP n'est **pas** compte comme flux de chapitres verifie.
2. Une oeuvre MangaDex avec des chapitres encore non lus les affiche des le premier controle dans le bilan (sans inventer des nouvelles publications). Les flux recents MangaDex restent bornes aux derniers chapitres par langue.
3. Les fiches de lecture HTML publiques deja associees produisent elles aussi un bilan (nombre de chapitres identifiables, non lus, dernier numero). Les pages bloquees/JS-only ont un etat d'echec explicite ; pas de fausse sortie.
4. Le premier controle d'un nouveau site reste une **reference de publication**, pour eviter 200 notifications de chapitres historiques. Le bilan des chapitres disponibles, lui, est affiche immediatement.
5. Sur une page de source ouverte dans l'application, l'icone **lier** dans la barre superieure associe l'URL courante a une oeuvre. Les pages liees seront verifiees lors du prochain controle. Le choix d'une fiche de serie plutot que l'accueil est indispensable.
6. Les couleurs, le lecteur, le shell et les animations ne sont pas modifies.

## Procedure de test

1. Extraire cette archive dans **un nouveau dossier**. Ne pas ecraser la version precedente.
2. Double-cliquer `Compiler-Windows.cmd`. Le script fait `flutter pub get`, `flutter analyze`, `flutter test`, puis la compilation EXE. Une erreur est a chercher dans `dist\\build-log.txt`.
3. Lancer `dist\\PazuluReader-0.4.7-windows\\pazulu_reader.exe` (apres compilation reussie).
4. Bibliotheque : garder une oeuvre MangaDex avec au moins un chapitre connu, marquer manuellement un ancien chapitre comme lu et verifier qu'il reste des chapitres superieurs.
5. Sorties > Verifier. La section **Resultat reel des verifications** affiche `MangaDex · EN` ou `FR` et le nombre de chapitres disponibles non lus, meme si la liste des **Nouvelles publications** est vide.
6. Decouvrir > Gérer mes sources > ouvrir une source, aller sur la fiche d'une oeuvre, cliquer l'icone de liaison dans l'entete. Choisir cette oeuvre dans la liste, puis la langue.
7. Sorties > Verifier. Une fiche HTML publique prise en charge affiche son nombre de chapitres ; les autres indiquent la cause de l'echec. Le bouton `Lire` ouvre soit le lecteur maison MangaDex, soit la page du chapitre dans la **seule** fenetre de l'application.
8. Refaire le controle apres publication d'un nouveau chapitre et verifier qu'une nouvelle notification est generee une fois, sans doublons aux controles suivants.
9. Tester les bascules rapides d'onglets, l'export de sauvegarde et la reprise de lecture.

## Limites verifiees dans le code et limites non validees

- MangaDex est le seul connecteur API natif complet livre. Ses chapitres publies uniquement sur des editeurs externes ouvrent le lecteur de l'editeur.
- Les autres sites exigent une association de fiche. Les pages HTML qui n'exposent pas une liste de chapitres ne peuvent pas etre annoncees comme verifiees. L'outil de capture depuis une WebView reste experimental.
- Les **13 adresses** restent dans le repertoire, mais le nombre de sources qui repondent a un simple test HTTP n'est pas le nombre de flux de chapitres effectivement controles.
- Pas de fonctionnement garanti si l'application est fermee. Les controles suivent les intervalles definis quand elle reste ouverte.
- Webtoon FR/EN et les plateformes protegees ne sont pas scrapées automatiquement ; leur consultation dans la webview n'est pas une permission de les copier.
- Aucun test HTTP vers les sites tiers, ni compilation Flutter Windows/Android n'a pu etre execute dans l'environnement de fabrication de cette archive. Les tests Dart fournis doivent etre executes par `Compiler-Windows.cmd`.

## Diagnostic si besoin

Utiliser `Diagnostic.cmd` en cas de fermeture brutale et transmettre `dist\\diagnostic.txt` et `dist\\build-log.txt` si la compilation echoue.
