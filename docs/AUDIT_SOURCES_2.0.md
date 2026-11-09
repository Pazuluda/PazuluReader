# Audit des sources — Pazulu Source Engine 2.0

Date : 6 novembre 2026. **Aucun domaine n’a pu être testé en conditions réelles depuis l’environnement de développement** (réseau limité aux dépôts de paquets). Aucun statut `FULL_READER` n’est donc attribué : il ne peut l’être qu’après un chapitre réellement chargé et validé dans Pazulu (bouton « Tester cette source » ou lecture), ce que le Diagnostic enregistre automatiquement.

## Synthèse

- Domaines audités : **214** (13 historiques + adresses du répertoire de 200 non dupliquées + 3 plateformes officielles demandées).
- Connecteurs réels livrés : 3 natifs (MangaDex, SushiScan.net, Pepper&Carrot) + 4 profils HTML déclaratifs désactivés par défaut.
- Répartition des statuts : UNVERIFIED : 208, EXTERNAL_ONLY : 4, SUBSCRIPTION_REQUIRED : 2.

Le fichier complet, triable, est `docs/AUDIT_SOURCES_2.0.csv`.

## Pourquoi pas plus de connecteurs « vérifiés » ?

1. Un profil HTML (famille Madara ou MangaThemesia) se valide en quelques minutes, mais **uniquement** contre le site réel : thème, protection d’images, Cloudflare et changements de domaine varient. Les 4 profils livrés sont donc désactivés jusqu’à un test réussi.
2. Les plateformes officielles payantes (Manga UP!, K MANGA, WEBTOON) ne sont pas intégrées en lecture : le moteur reconnaît leurs pages de restriction et cherche un véritable équivalent ailleurs, sans contournement.
3. Ajouter une source = écrire un manifeste JSON (voir `docs/EXTENSIONS_2.0.md`), l’installer, cliquer « Tester cette source ». Aucune recompilation.

## Sources prioritaires

| Nom | Domaine | Extension | Statut | Note |
|---|---|---|---|---|
| ManhuaUS | manhuaus.com | pazulu.manhuaus | UNVERIFIED (profil Madara, IMPLEMENTED_UNTESTED, désactivé) | Activer puis tester. |
| AsuraScans | asurascans.com | — | UNVERIFIED | Site devenu une application JavaScript propriétaire (lecteur non HTML classique) : pas de profil livré ; candidat transport « browser » à écrire et valider sur Windows. |
| Scan-Manga | scan-manga.com | — | UNVERIFIED | Lecteur à protection d’images connue : aucune extraction tant qu’un test réel n’a pas montré des images publiques non protégées. |
| EN-ThunderScans | en-thunderscans.com | pazulu.thunderscans | UNVERIFIED (profil MangaThemesia + WebView2, IMPLEMENTED_UNTESTED, désactivé) | Activer puis tester. |
| ManhuaTop | manhuatop.org | pazulu.manhuatop | UNVERIFIED (profil Madara, IMPLEMENTED_UNTESTED, désactivé) | Activer puis tester. |
| MangaDex | mangadex.org | pazulu.mangadex | UNVERIFIED (connecteur API natif, VERIFIED_FIXTURE_ONLY) | Connecteur API officiel. Nombre de pages fourni par l’API : FULL_READER attendu après un test réel « Tester cette source ». |
| KingofShojo | kingofshojo.com | pazulu.kingofshojo | UNVERIFIED (profil MangaThemesia + WebView2, IMPLEMENTED_UNTESTED, désactivé) | Activer puis tester. |
| WEBTOON FR | webtoons.com | — | EXTERNAL_ONLY (politique) | Plateforme officielle : conditions d’utilisation interdisant l’extraction ; accès via le site officiel uniquement. |
| WEBTOON EN | webtoons.com | — | EXTERNAL_ONLY (politique) | Plateforme officielle : conditions d’utilisation interdisant l’extraction ; accès via le site officiel uniquement. |
| sushiscan | sushiscan.net | pazulu.sushiscan | UNVERIFIED (connecteur natif, VERIFIED_FIXTURE_ONLY) | Liste ts_reader lue dans le HTML public ; repli WebView2 invisible page par page. |
| Manga UP! | manga-up.com | — | SUBSCRIPTION_REQUIRED (a priori, non vérifié) | Chapitres gratuits temporaires puis payants (« n’est plus gratuit »). Pas d’API publique documentée : aucune extraction ; la page de restriction est détectée (Test B). |
| K MANGA | kmanga.kodansha.com | — | SUBSCRIPTION_REQUIRED / LOGIN_REQUIRED (a priori, non vérifié) | Points, connexion et vérification d’âge selon les titres : détectés, jamais contournés (Test C). |
| MANGA Plus | mangaplus.shueisha.co.jp | — | EXTERNAL_ONLY (politique) | Liens « externalUrl » de MangaDex : jamais traités comme des pages. |

## Statuts utilisés

`FULL_READER`, `PARTIAL_READER`, `METADATA_ONLY`, `EXTERNAL_ONLY`, `LOGIN_REQUIRED`, `SUBSCRIPTION_REQUIRED`, `BLOCKED`, `BROKEN`, `UNVERIFIED` — calculés par `SourceTestRunner` et affichés dans Paramètres → Moteur Pazulu → Diagnostic des sources.
