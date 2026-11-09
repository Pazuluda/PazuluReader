# Catalogue v0.4.0 — état de compatibilité

La présence d'un site dans ce catalogue ne signifie pas que les images peuvent être copiées ou téléchargées. Les sites n'ayant pas d'intégration autorisée sont des **liens vers leurs pages**. Le téléchargement hors ligne n'est actuellement proposé qu'aux sources compatibles, en pratique MangaDex.

| Site | Langue initiale | Accès depuis l'app | Recherche/chapitres/CBZ intégrés | Détection auto |
| --- | --- | --- | --- | --- |
| ManhuaFast | EN | Lien HTTPS | Non | Non |
| ManhuaUS | EN | Lien HTTPS | Non | Non |
| AsuraScans | EN | Lien HTTPS | Non | Non |
| Aethon Webcomics | EN | Lien HTTPS | Non | Non |
| ManhwaClan | EN | Lien HTTPS | Non | Non |
| Scan-Manga | FR | Lien HTTPS | Non | Non |
| EN-ThunderScans | EN | Lien HTTPS | Non | Non |
| ToonGod | EN | Lien HTTPS | Non | Non |
| Swordhound | EN | Lien HTTPS | Non | Non |
| SSS-Class Hunter | EN | Lien HTTPS | Non | Non |
| ManhuaTop | EN | Lien HTTPS | Non | Non |
| MangaDex | EN, FR | Lien + connecteur | Oui, si accessible | Oui, application ouverte |
| KingofShojo | EN | Lien HTTPS | Non | Non |
| WEBTOON FR | FR | Lien HTTPS | Non | Non |
| WEBTOON EN | EN | Lien HTTPS | Non | Non |

À ne pas confondre : le lien vers un site n'est pas une extension installée. Si une source dispose d'une API officielle / un flux autorisé et d'une permission d'intégration, un `ContentSource` dédié pourra fournir `search`, `listChapters`, `latestChapters` et `getPages` (pour les images autorisées) sans toucher au lecteur maison.

La surveillance des traductions FR/EN v0.4.0 utilise le retour du connecteur MangaDex, et non une estimation de calendrier. La vérification automatique est mise en pause lorsque l'application est en arrière-plan. Les notifications du système d'exploitation ne sont pas encore implémentées.
