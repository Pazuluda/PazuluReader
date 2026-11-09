# Pazulu Reader 0.4.10 — Decouverte puis lecture a la demande

## Contrat fonctionnel

1. **Decouvrir / rechercher** interroge uniquement les catalogues de metadata des connecteurs installes. Aucun fichier de chapitre n'est charge. Les couvertures (comme toute interface catalogue) restent des images de presentation.
2. **Ouvrir une fiche** affiche resume, langues, liens, liste de chapitres et progression. Les titres et chapitres sont des metadata, pas des images en cache.
3. **Appuyer sur Lire / Reprendre** ouvre le lecteur Pazulu dans la meme fenetre. Si le chapitre n'est pas deja conserve, le moteur recupere automatiquement les images via le connecteur autorise et construit un CBZ interne. Une barre de progression s'affiche.
4. **Ouvrir de nouveau le meme chapitre** relit le CBZ local (pas de nouveau transfert d'images).
5. **Passer au chapitre suivant** applique la meme regle au nouveau chapitre, jamais a toute la serie.
6. En cas de cache indisponible (disque plein, image de challenge HTML, source indisponible), le lecteur tente une lecture reseau via le connecteur et explique l'erreur si elle persiste.

## Connecteurs natifs inclus

- **MangaDex** : recherche, chapitres et images via ses interfaces documentees, en respectant limites et credits.
- **Pepper&Carrot (source libre de demonstration)** : recherche de la serie, index `episodes.json` FR/EN et images construites selon l'API publiee par l'auteur. Ce connecteur illustre le fonctionnement d'un second catalogue et l'acces paresseux aux pages ; il ne fait pas partie des 13 adresses personnelles.

Les **13 sources du catalogue personnel** sont conservees, y compris leur sante et leur mode de navigation. Leur presence dans le repertoire **ne vaut pas** verification de connecteur de lecture. Pour leurs pages qui autorisent l'integration, la capture de session existante et le cache CBZ peuvent etre utilises, sans contourner authentification, paywall ou DRM. Aucun nouveau site n'est presente a tort comme compatible automatiquement.

## Tests a effectuer sous Windows

- Double-cliquer sur `Compiler-Windows.cmd` ; le rapport est `dist/build-log.txt`.
- Dans **Decouvrir**, rechercher `Pepper` : la fiche et le resume doivent s'afficher immediatement sans aucun telechargement CBZ.
- Ouvrir la fiche puis cliquer **Lire** sur un episode FR/EN, puis verifier la barre de progression et l'image dans le lecteur maison.
- Revenir a la fiche, relire le meme chapitre et verifier qu'aucun nouveau telechargement ne se produit.
- Dans **Reglages > Lecture**, desactiver le cache automatique : les pages restent consultables en ligne lorsque le connecteur le permet.
- Tester une source HTML inaccessible : le logiciel ne doit pas enregistrer du HTML comme CBZ.
- Verifier que les bibliotheques et les progres des versions precedentes se chargent sans migration destructive.

## Limites

- Le lecteur attend actuellement de finir la mise en cache du chapitre avant son premier affichage. Il ne telecharge **pas toute la serie** d'un coup.
- Le temps de chargement initial depend du nombre d'images, de la connexion et de la politique du site.
- Les sources tierces sans connecteur valide restent accessibles dans la fenetre unique par la navigation existante ; on ne promet pas leur extraction automatique.
- Validation du build Windows, des tests Flutter et des vraies requetes reseau a effectuer sur la machine cible : SDK Flutter absent dans cet environnement.
