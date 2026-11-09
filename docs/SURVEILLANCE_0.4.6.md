# Pazulu Reader 0.4.6 — Surveillance des chapitres par oeuvre

## Ce qui fonctionne dans le code

- Le connecteur MangaDex conserve sa detection de nouveautes via l'API existante.
- En plus, Pazulu peut verifier **la page d'une oeuvre que tu as liee toi-meme** : Fiche de l'oeuvre > Autres sources > Lier un site.
- Si la page HTTPS publique contient des liens HTML de chapitres identifies (« Chapter 31 », « Chapitre 31 », « Episode 31 » ou URL analogue), ils servent de catalogue de references, **pas de fichiers telecharges**.
- Un premier controle reussissant devient un point de depart **sans envoyer de notifications pour les anciens chapitres**. Les nouveaux liens sont visibles dans Nouveautes, avec langue FR/EN, numero et site.
- Un clic sur la nouveaute ouvre le chapitre dans la vue officielle integree a Pazulu ; si le site autorise l'analyse des pages, le bouton « Lire dans Pazulu » peut ensuite utiliser le moteur experimental de la version precedente.
- La progression et les historiques sont enregistres dans `library.json` et les sauvegardes `.pazulu` deja utilisees par le logiciel.

## Mode d'emploi

1. Ouvre une oeuvre dans la bibliotheque (ou cree une fiche manuelle).
2. Descends a « AUTRES SOURCES », puis « Lier un site ».
3. Choisis la source (AsuraScans, Scan-Manga, etc.), la langue, et surtout **l'URL de la fiche de cette oeuvre**, pas la page d'accueil du site.
4. L'ajout du premier lien active la surveillance de cette oeuvre. Tu peux la desactiver via sa fiche.
5. Dans **Nouveautes**, clique sur **Verifier**. Le premier controle constitue la reference.
6. Reviens plus tard : si un chapitre supplementaire apparait dans le HTML autorise, la notification est ajoutee.

## Limites intentionnelles

- **13 sites dans le catalogue ne veut pas dire 13 extracteurs valides**. Cette version ajoute un lecteur generique de *listes de chapitres HTML*. Pas une garantie de compatibilite pour chaque fournisseur.
- Les sites qui necessitent du JavaScript, des connexions, une session ou des protections anti-bot ne sont pas automatiquement verifies. Aucun blocage ou DRM n'est contourne.
- WEBTOON FR/EN et Aethon, en mode officiel, restent hors surveillance generique. MangaDex reste natif.
- Une notification atteste la presence d'un **lien identifiable dans la page HTML**, pas la disponibilite de toutes les images du chapitre ou le droit de le telecharger.
- Pas de surveillance lorsque Pazulu Reader est ferme. Pour les sites non natifs, les controles automatiques se font au maximum toutes les 30 minutes par fiche ; le bouton manuel autorise un nouveau controle apres 5 minutes. Une serie de controles est limitee a 10 fiches (20 en manuel) pour eviter de solliciter trop de sites.
- Les erreurs (403, 429, 525, redirect, page vide, JS, captcha) ne sont pas interpretees comme de nouvelles sorties. Les catalogues sans liens ne remplacent pas un historique existant.
- Les horaires de planning seront un indice utile a une version future ; ils ne sont pas encore branches.
- Aucun changement de DA : palettes, animation, HUD, structure du lecteur et navigation V0.4.5 conserves.

## Controle apres compilation

1. Lancer `Compiler-Windows.cmd`, lancer les tests Flutter.
2. Verifier la navigation rapide entre les onglets (correctif V0.4.5 conserve).
3. Lier une URL de fiche de series sur une page HTML publique et verifier deux fois : aucune ancienne sortie lors du premier controle, nouveaute seulement apres la parution reelle d'un nouveau lien.
4. Essayer une page dynamique ou en maintenance : message de « source non verifiable », mais aucune fausse alerte.
5. Fermer/rouvrir l'application, verifier que l'historique des chapitres observes et les liens ont ete preserves ; tester un export/import `.pazulu`.
6. Si compilation/plantage : `dist/build-log.txt` ou `Diagnostic.cmd` puis `dist/diagnostic.txt`.

Compilation et execution Flutter Windows/Android : non realisees dans l'environnement de preparation du code.
