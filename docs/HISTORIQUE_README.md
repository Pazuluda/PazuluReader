# Pazulu Reader 2.3.24 — Pazulu Source Engine 2.0

**2.3.1 :** toutes les sources au même niveau (aucune référence, MangaDex compris), recherche immédiate sur tous les sites quand une œuvre n'a rien, dates de sortie « il y a… » sur chaque chapitre, planning en frise horaire.

**2.3 :** planning de la semaine de toutes les sorties (animés, EN, FR) heure par heure, « Ma liste », chapitres manquants complétés automatiquement pour toute la bibliothèque, Découvrir par catégories et sans lag, Profil avec niveaux et succès.

**2.2 :** animés (AniList : horaires, épisodes vus, liens officiels), planning à l'heure près avec pauses, hiatus, reprises et nouvelles saisons, chapitres affichés instantanément et rafraîchis en arrière-plan, nouvelle interface et nouveau lecteur.

**2.1 :** recherche obligatoire sur tous les sites, lecture réelle des chapitres des sites web (validée), Découvrir rempli par tous les catalogues, onglet Planning (sorties EN/FR et mes lectures). Voir `docs/CHANGELOG.md`.

Application Windows Flutter/Dart, identité Indigo/violet conservée, aucune donnée personnelle migrée de force.

- **Moteur indépendant de l'interface** (`lib/engine/`) : client HTTP sûr (HTTPS, domaines déclarés, anti-SSRF, 429/Retry-After, circuit breaker, déduplication, cache LRU), validation réelle des pages (octets, dimensions, paywall, âge, erreurs), identité canonique des chapitres (115.1 ≠ 115.2, Extra ≠ chapitre 1, roman ≠ manga), Smart Source Router avec repli vers un **vrai équivalent** uniquement.
- **Extensions Pazulu** (`.pazulusource`, `.pazulupack`) : manifestes JSON validés, installation atomique, retour arrière, désactivation individuelle, intégrité SHA-256. Aucun code tiers exécuté.
- **Lecteur 1 / 2 / 3** : vraies sources, langue, état vérifié, « Rechercher une autre source », basculement automatique réglable, double page, ajustement, sens mémorisé par œuvre.
- **Diagnostic des sources** : état, version, temps de réponse, dernière erreur, « Tester cette source », journal exportable expurgé.

Documentation : `docs/MOTEUR_2.0.md` (audit V0.5.4 + architecture), `docs/EXTENSIONS_2.0.md`, `docs/AUDIT_SOURCES_2.0.md`, `docs/TESTS_2.0.md`, `docs/INSTALLATION_2.0.md`.

**Important :** cette version a été écrite sans pouvoir compiler ni exécuter Flutter/Dart (voir `docs/TESTS_2.0.md`). Lancez `Compiler-Windows.cmd` et envoyez `dist\build-log.txt` en cas d'erreur avant de la considérer comme stable.

Non livré : lecture texte des light novels / webnovels (aucune source texte intégrée ; un chapitre sans image n'est jamais transformé en fausse planche), persistance SQLite (`drift`), migration `webview_flutter_windows`, vérification de signature des packs.

## Historique V0.5.4 — Moteur de lecture natif + repli WebView2 intégré

Application Flutter Windows, interface indigo existante conservée.

- Aucun serveur Suwayomi, aucune extension Keiyoushi, aucun processus Java externe.
- Pour SushiScan, Pazulu examine systematiquement le lecteur rendu en WebView2 invisible, detecte la pagination et reconstitue toutes les pages exposees avant d afficher le chapitre natif. Si le total annonce ne peut pas etre charge, il affiche une erreur plutot qu un faux 1/1.
- La lecture intégrée via WebView2 dépend du site : le mode site ne télécharge pas de CBZ et ne synchronise pas automatiquement la position.
- Connecteurs intégrés : MangaDex (API publique), Pepper&Carrot (BD sous licence libre), SushiScan.net (adaptateur HTTP/HTML natif expérimental).
- Recherche -> fiche -> chapitres/volumes -> URLs de pages seulement lors de l'ouverture de la lecture -> cache CBZ -> progression personnelle locale.
- Le catalogue de 209 adresses est conservé comme signets et n'est pas présenté comme 209 connecteurs actifs.
- Les données des anciennes versions restent dans le dossier de données de Pazulu Reader. Une sauvegarde est recommandée avant mise à jour.
- Les liens Suwayomi sauvegardés ne deviennent pas des liens natifs automatiquement ; rattachez les éditions depuis « Associer une source Pazulu ». Les CBZ précédemment créés sont conservés.
- Les sources peuvent limiter ou retirer leur contenu. Le moteur ne contourne pas les protections techniques, paywalls, logins ou contenus retirés.

## Compiler sur Windows

Lancer `Compiler-Windows.cmd` avec Flutter SDK et outils Visual Studio C++ déjà installés. Le script doit afficher une erreur en cas d'échec de compilation.

## Test intégré

Sur `Découvrir`, rechercher `Solo Leveling`, ou ouvrir `Sources de lecture -> Moteur Pazulu intégré` et exécuter les tests de connecteurs à la demande. Dans `Associer une source Pazulu`, choisir une édition et ouvrir le lecteur.

## Limites honnêtes

Le connecteur SushiScan et le repli WebView2 disposent de tests de parseur déterministes avec fixtures. L'accès Internet et Flutter ne sont pas disponibles dans l'environnement de création de cette archive : le site et le binaire Windows n'ont **pas** été testés en réel ici. Le chargement des pages peut donc échouer si le HTML/les accès du site ont changé. Seule une vérification sur Windows peut confirmer le parcours complet.

## V0.5.2 — Lecteur Pazulu exclusivement
La page WebView2 ne s affiche plus a l utilisateur. Apres echec du parseur HTML, le moteur tente d extraire automatiquement les URL images du DOM rendu dans une WebView invisible. Si la source ne donne pas les planches, une erreur claire remplace l ancien affichage du site.

## V0.5.3 - correctif de pagination
- Le chapitre SushiScan est analyse dans le DOM rendu, meme quand le HTML initial ne fournit qu une image.
- Gestion des lecteurs utilisant un selecteur de pages (1/14, 2/14, etc.).
- Pilotage du controle de navigation visible et relecture du DOM jusqu a collecte complete, sans construction arbitraire d URL.
- Une seule image ne valide plus un chapitre dont le total annonce est superieur.
- Les chapitres incomplets ne sont pas marques lus et le lecteur natif ne montre pas d interface externe.
- Tests de pagination ajoutes ; une simulation JavaScript de 14 pages a ete executee localement.
- IMPORTANT : ni compilation Flutter Windows ni test WebView2 sur SushiScan en conditions reelles ici. Le passage d une page a la suivante depend du DOM reel du site et necessite validation sur Windows.


## Correctif V0.5.3 packaging (6 novembre 2026)

- `Compiler-Windows.cmd` signale les echecs de tests et poursuit la compilation de la version Windows.
- Si `pazulu_reader.exe` tourne, la compression ZIP est reportee au lieu de casser le packaging de l'installateur.
- Fermez d'abord Pazulu Reader, puis lancez `Packager-Windows.cmd` pour recreer **seulement** l'archive depuis `dist/PazuluReader-0.5.3-windows` sans relancer Flutter.
- Correctif HTML: la concatenation des labels d'un select (`1/14` puis `2/14`) ne doit pas etre interpretee comme un compteur `1/142`.
- Le test de recherche ne compte plus la visite de chapitre effectuee explicitement lors de la resolution initiale d'une URL collee.

Remarque : ces correctifs ont ete inspectes statiquement et une simulation JavaScript a ete effectuee; la validation Flutter Windows doit etre faite sur un environnement avec Flutter installe.

## Correctifs V2.0.0

Voir `docs/V2.0.0_FAILOVER.md` pour le fonctionnement des lecteurs de secours et les limites.
