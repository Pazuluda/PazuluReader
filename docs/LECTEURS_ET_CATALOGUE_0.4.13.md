# V0.4.13 — Choix des lecteurs et catalogue de suggestions

## Correctifs et comportement réel

- Les liens éditeur `externalUrl` de MangaDex sont traités comme des **liens externes**, même si les métadonnées annoncent des pages. Pas de requête "at-home" sur ces chapitres : un 404 signifie souvent que MangaDex n'héberge pas les images.
- Dans chaque chapitre, les deux premières variantes restent visibles et **Voir les N versions** ouvre la liste complète : langue, groupe, lecteur natif ou lien externe.
- Un lien externe ne déclenche plus la lecture d'une fausse image ou un téléchargement automatique. Il ouvre un dialogue précisant que l'accès peut être expiré, payant ou indisponible. L'ouverture du site se fait uniquement après confirmation dans la **même fenêtre Pazulu**. « Lien indisponible » l'identifie dans la session (pas de fausse vérification à distance).
- Les chapitres réellement natifs restent prioritaires, conservent la reprise et le téléchargement à la demande. Le lecteur tente un autre connecteur natif lorsqu'un chargement échoue.
- La vue de lecture d'un lien externe n'est plus présentée comme un chapitre 1/1 hors ligne : elle montre l'état réel et propose l'accès interne à la page officielle.

## Liste de 200 adresses fournie

L'écran **Sources → Explorer 200 sites suggérés** présente les 200 domaines du document fourni (53 FR / 147 EN) sous forme de suggestions avec recherche et filtres. Les statuts historiques sont étiquetés comme **non revérifiés** : 104 annoncés « accueil/catalogue accessible », 10 « partiel », 86 « non confirmé ».

Un clic sur **Ajouter** enregistre l'adresse en source personnelle et lance le contrôle habituel de disponibilité du site. Cela **n'installe pas** un connecteur natif de recherche, de chapitres ou d'images. Aucun des 200 sites n'est activé de force. Les 13 sites par défaut et les anciennes données restent intacts.

## Ce qui reste à développer

- Connecteurs compatibles et autorisés, testés **site par site** : recherche réelle, catalogue paginé, pages téléchargeables, gestion des redirections et des indisponibilités.
- Association automatique fiable des œuvres entre sites, sans confondre titres voisins.
- Détection et diagnostic des liens 404 en temps réel **sans supposer qu'un HEAD HTTP suffit** ; certains sites refusent ce type de requête.
- Affichage d'un état de licence / accès payant attesté par source. Aucun contrôle technique, paywall ou DRM n'est contourné.

## Validation

Les scénarios de classement natif/externe, la liste de 200 suggestions, les domaines bloqués et la distinction pages/liens externes ont des tests Flutter dans `test/multisource_v0413_test.dart`. L'environnement de création ne dispose pas du SDK Flutter : **la compilation Windows et l'exécution des tests restent à faire sur le PC Windows**. À lancer avec `Compiler-Windows.cmd` ; transmettre `dist/build-log.txt` en cas d'erreur.
