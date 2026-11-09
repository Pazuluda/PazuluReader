# Validation Pazulu Reader 0.4.9

## Objectif

Une oeuvre Pazulu, plusieurs langues/sources, un seul historique. Un clic
Sorties ne doit pas afficher automatiquement le site web a la place du lecteur.

## Parcours a verifier

1. Compiler depuis `Compiler-Windows.cmd` ; le script execute `flutter analyze`
   et `flutter test` avant le build. Conserver `dist/build-log.txt`.
2. Sur une oeuvre MangaDex avec pages disponibles, ouvrir Sorties > Reprendre
   dans Pazulu ; verifier l'affichage du HUD et la memorisation de la page.
3. Importer `Chapitre 16.cbz` dans **la meme oeuvre** depuis sa fiche.
   Verifier que Ch. 16 apparait en FR/EN selon le choix, sans doublon de livre.
4. Fermer/redemarrer, reprendre. Le numero et la progression doivent persister.
5. Ouvrir une page de chapitre d'une source DOM compatible, cliquer Lire dans
   Pazulu ; verifier le numero pre-rempli et corriger si besoin ; choisir la
   meme oeuvre (ou en creer une si necessaire), puis CBZ et lire.
6. Si la page ne fournit pas d'images valides, afficher une erreur expliquee ;
   ne pas pretendre qu'un telechargement a reussi.
7. Pour une publication connue sans pages/CBZ, confirmer le dialogue qui
   propose l'import, plutot qu'une page web automatique.
8. Tester 40 changements rapides d'onglet et les six palettes, sans crash.

## Limites

- Compilation Flutter et test runtime sur Windows non realises ici.
- Tous les sites n'autorisent pas l'extraction, les pages protegees ne sont pas
  prises en charge. Les deux sources archivees restent archivees.
- Le scan HTML publique identifie des liens, pas necessairement des images.
- Les archives d'un fichier sans numero demandent une saisie manuelle ; pour
  plusieurs archives, les nommer explicitement `Chapitre 1.cbz`, etc.
