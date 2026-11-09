# V0.4.11 — Chapitres et lecteurs : états fiables

- Les badges « Manquants en FR/EN » ont été supprimés : un numéro élevé dans un catalogue partiel ne signifie pas que tous les chapitres intermédiaires sont absents.
- L'interface distingue les chapitres effectivement répertoriés, lisibles dans Pazulu, et disponibles seulement dans un lecteur officiel.
- Le bouton de recherche explore les connecteurs natifs installés, vérifie les titres ou leurs alias, et refuse les correspondances floues. Il ne télécharge aucune page avant lecture.
- Les liens trouvés sont conservés en bibliothèque ou en session. Requêtes concurrentes mutualisées, chargement parallèle et délais limités.
- L'import CBZ reste en option dans le menu secondaire, et non comme action principale.
- Les 13 sites personnalisés sont préservés, mais tous ne fournissent pas de connecteurs natifs : cette V0.4.11 ne prétend pas avoir résolu leur extraction.

## Vérification sous Windows

1. Double-cliquer sur `Compiler-Windows.cmd`, puis vérifier `dist/build-log.txt`.
2. Sur One Piece, vérifier que l'application n'invente plus 1000 chapitres manquants.
3. Sur Solo Leveling, vérifier le nombre de chapitres recensés et celui réellement lisible dans Pazulu.
4. Essayer « Explorer les autres lecteurs » : le résultat indique uniquement les sources testées.
5. Vérifier la lecture de chapitres, la bibliothèque et la progression existantes.

**Validation :** Le SDK Flutter Windows n'est pas présent dans l'environnement d'assemblage. Le projet et les tests doivent encore être compilés sur le PC cible.
