# Pazulu Reader V0.4.14 — Fiche d'œuvre et choix des sources

## Objectif

Ne plus confondre un annuaire de sites, un index de chapitres et un lecteur
qui sait réellement récupérer les images. Préserver la direction artistique
indigo/violet, la fenêtre unique, les préférences et la bibliothèque locale.

## Changements effectifs dans le code

- Fiche d'œuvre réorganisée en une composition responsive, couverture compacte,
  résumé replié, boutons non superposés ; genres et diagnostic repliables.
- Lignes de chapitres simplifiées : un sélecteur donne accès à **toutes les
  variantes recensées** et précise leur statut externe/natif.
- `SourceRouting` est le moteur de sélection commun : cache CBZ existant en
  priorité, puis connecteurs disponibles, puis liens externes d'éditeur.
- Lors d'une erreur dans le chargement du chapitre, l'identifiant du chapitre
  est temporairement rétrogradé pendant 30 minutes ; une autre variante native
  peut prendre le relais automatiquement si elle existe.
- Une erreur d'image permet d'essayer l'URL basse qualité si elle existe, ou
  un autre lecteur natif du même chapitre. Pas de bouton « réessayer » trompeur
  en l'absence de solution.
- Les liens externes **ne marquent plus les chapitres comme lus** à l'ouverture
  d'une fiche sans pages.
- Le message « lecteur indisponible » n'impose plus un import CBZ. L'import
  reste disponible dans le menu secondaire.
- Correspondance stricte des titres alternatifs entre familles manga, manhwa,
  manhua et webtoon ; pas de fusion automatique avec les romans.
- L'index HTML des sources liées reconnaît aussi les menus déroulants de
  chapitres et les attributs de numérotation, sans télécharger les images.
- Le moteur d'inspection n'utilise plus de grandes images de pages d'accueil
  comme substituts de chapitres quand les conteneurs de lecture manquent.

## Ce qui reste limité — ne pas présenter comme acquis

- Les treize sites du catalogue ne sont **pas** treize connecteurs natifs.
  MangaDex et Pepper&Carrot sont les deux connecteurs natifs actuellement
  intégrés, et même eux peuvent présenter des chapitres uniquement externes.
- Les 200 sites du fichier utilisateur constituent des **suggestions**, pas des
  lecteurs validés ni des téléchargements garantis.
- Le système HTML de chapitres n'accède qu'aux listes publiques accessibles
  sur les fiches explicitement associées. Il n'extrait pas le contenu de
  services protégés ni les pages payantes.
- Une œuvre comme Solo Leveling peut donc toujours n'afficher que 15 chapitres
  officiels chez MangaDex. Cela ne signifie pas que la série ne comporte que
  15 chapitres.
- Les dates/limites de chaque source doivent être confirmées en conditions
  réelles avant d'être affichées comme une disponibilité de lecture.

## Validation et compilation

Tests ajoutés : `source_routing_v0414_test.dart`,
`source_matching_v0414_test.dart`, `chapter_listing_v0414_test.dart`.

Aucun SDK Flutter/Dart n'est présent dans l'environnement de génération :
les tests Dart et la compilation Windows **n'ont pas pu être exécutés ici**.
Compiler avec `Compiler-Windows.cmd`, puis envoyer `dist/build-log.txt` si une
étape échoue. Les fichiers de sauvegarde existants ne sont pas réinitialisés.
