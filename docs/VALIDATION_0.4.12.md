# Pazulu Reader V0.4.12 — Validation de la couverture des chapitres

## Ce que cette version corrige

- Recherche automatique, toutes les 6 heures au maximum par oeuvre, parmi les **connecteurs natifs déjà installés**. Elle ne parcourt pas automatiquement les 13 sites du répertoire, qui ne sont pas tous des connecteurs.
- Rafraîchissement des listes après 20 minutes ; **Actualiser** force un contrôle immédiat.
- Une source en erreur conserve les chapitres précédemment observés en mode **à revérifier**. Une réponse réussie mais vide les remplace correctement.
- Une fiche d'oeuvre reliée manuellement à une URL de source compatible peut ajouter les numéros des chapitres de sa liste HTML publique à la fiche. Pas d'images récupérées avant Lire ; pas de DRM ni d'accès payant contourné.
- Les sources actives, vides, en erreur ou officielles sont clairement distinguées dans la fiche.
- Le lecteur maison, la direction artistique et les sauvegardes sont préservés.

## Limites réelles

- Les 13 domaines du répertoire ne sont **pas** 13 connecteurs de lecture natifs. Les seuls connecteurs natifs installés sont MangaDex et Pepper&Carrot ; la capture de session existante peut servir à des chapitres explicitement importés.
- Le fait qu'un site annonce un chapitre ne signifie pas que ses pages peuvent être chargées dans notre lecteur maison.
- Les catalogues officiels peuvent volontairement n'afficher qu'une partie des chapitres d'une série. L'application ne doit ni inventer les numéros intermédiaires, ni les annoncer disponibles.
- Les listes uniquement JavaScript, les accès restreints, les anti-bots et les sites indisponibles sont signalés plutôt que contournés.

## Tests sur Windows (Flutter 3.47.x)

1. Double-cliquer `Compiler-Windows.cmd`. Vérifier zéro erreur dans `dist/build-log.txt`.
2. Rechercher One Piece, ouvrir la fiche et examiner **Couverture des sources**. L'absence de 1000 chapitres doit être expliquée comme couverture limitée et non comme 1000 chapitres supprimés.
3. Rechercher One-Punch Man. Le nombre recensé doit correspondre aux catalogues réellement consultés ; aucun chapitre ne doit être inventé.
4. Dans Bibliothèque, associer une URL **de fiche d'oeuvre** sur un site compatible (pas la page d'accueil), puis rouvrir la fiche. Les numéros de cette liste publique pourront apparaître dans le regroupement ; le lecteur intégré n'est utilisable que si les pages sont accessibles et autorisées.
5. Simuler une coupure réseau après un premier contrôle réussi, puis actualiser. Les anciens chapitres doivent rester mais avec statut **À revérifier**.
6. Vérifier les chapitres CBZ téléchargés précédemment, les favoris, les six palettes et la navigation rapide.

Les tests Dart/Flutter et la compilation Windows ne peuvent pas être exécutés depuis l'environnement de préparation actuel. Ils sont à valider sur le PC Windows de l'utilisateur.
