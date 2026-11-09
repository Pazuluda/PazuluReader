# V0.4.19 - Correctif de validation et installation du moteur

Cette version ne prétend pas ajouter 209 lecteurs fonctionnels.

## Modifications

- Correction du regroupement trop large entre manga et webtoon : on conserve par défaut les mangas séparés des webtoons (manhwa/webtoon restent compatibles).
- Correction de l'URL de recherche publique suffixée par `#`.
- Correction des débordements `RenderFlex` dans **Sorties** à petite largeur.
- Version du ZIP Windows alignée sur la version du projet (`0.4.19`).
- Ajout du script **Installer-Moteur-Extensions.cmd** pour récupérer volontairement le MSI officiel de Suwayomi, avec contrôle de taille et SHA256 lorsque fourni par GitHub. Aucune extension tierce n'est installée automatiquement.

## Activation des sources

1. Exécuter `Installer-Moteur-Extensions.cmd` puis installer et démarrer Suwayomi.
2. Configurer son écoute sur `127.0.0.1:4567` et sélectionner des dépôts d'extensions de confiance dans Suwayomi.
3. Installer volontairement des extensions FR/EN puis lancer `Verifier-Moteur-Extensions.cmd` et `Diagnostiquer-Sources.cmd`.
4. Relancer Pazulu et cliquer sur rechercher une source.

Les adresses d'un catalogue ne sont pas des extensions : il faut valider recherche -> chapitres -> pages pour chaque source. Le fait que Scan-Manga fonctionne dans un navigateur ne garantit pas que son ancienne extension soit opérationnelle (erreurs 404/Cloudflare documentées).

Tests automatisés ajoutés : cohérence des types, URL sans fragment, non-régression responsive. **Flutter n'est pas disponible ici : tests et compilation non exécutés.**
