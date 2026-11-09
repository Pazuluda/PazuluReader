# 2.3.24 — 9 novembre 2026

- Mythic Item Obtained revenu à 195 (journal + liste réelle) : manganato / mangabats, maintenant lus en entier, ont un « 195 » — mais leur numérotation est différente : leur « 194 » est daté du 12 juin, le vrai 194 est sorti le 25 août. Règle générale : un site dont les chapitres sont datés plus de 2 semaines AVANT leur sortie sur les autres sites (pour les chapitres sortis après sa première date) numérote autrement → mis de côté pour cette œuvre (noté dans le journal). Un site qui copie tout en un jour, plus tard, reste.
- « Reprendre » ne rouvre jamais un chapitre « non confirmé » : retour au dernier chapitre confirmé.
- Écran noir à l'ouverture d'une copie hors ligne longue (147 pages) : la vérification des images se fait en arrière-plan (elle bloquait l'affichage).

# 2.3.23 — 9 novembre 2026

Constaté sur les données réelles de Catastrophic Necromancer (318–319 sans date) :
- manganato / mangabats (famille MangaNato) : la page ne contient qu'un lien ; la liste complète, avec les dates, est chargée depuis une adresse JSON écrite dans la page (`data-api-url …/api/manga/__SLUG__/chapters`). Elle est maintenant lue, page après page (fini les « 1 ch. » / « 2 ch. »).
- mangaread donne la date de 312 chapitres sur 319 mais pas des 3 plus récents : la page est enregistrée dans `diagnostics\…-liste-sans-date.html` pour lire comment ce site écrit les chapitres « nouveaux ».
- Tests : `test/v2323_manganato_test.dart`.

# 2.3.22 — 9 novembre 2026

- « Date de sortie inconnue » (Catastrophic Necromancer 318–319) : quand aucun site n'écrit la date à côté du chapitre, l'app prend, dans l'ordre :
  1. l'heure la plus ancienne à laquelle un site l'a montré dans ses « dernières sorties » (ou MangaDex) — le site qui l'a sorti en premier — « Sorti … » ;
  2. la notification de nouveau chapitre — « Repéré … » ;
  3. le moment où l'app l'a vu pour la première fois sur un site (gardé sur disque, jamais pour les anciens chapitres d'une première liste) — « Repéré … ».
- Tests : `test/v2322_dates_test.dart`.

# 2.3.21 — 9 novembre 2026

Constaté sur la liste réelle de Mythic Item Obtained (EN « + 10 spéciaux » contre 2 en FR) :
- Chapitres découpés en morceaux par certains sites (90.1 … 90.4 chez arenascan / KingofShojo / mangazin, 95.1–95.2 chez mangazin, 1.1–1.2 chez linkmanga) : morceaux masqués quand au moins 2 sites ont le chapitre entier. Un vrai « .5 » seul (107.5) n'est jamais touché ; des morceaux que personne n'a en entier restent. Règle appliquée à toutes les œuvres et à tout site ajouté plus tard ; chaque masquage est noté dans le journal.
- Une copie hors ligne ne donne plus de « date de sortie » (son heure d'enregistrement passait pour une sortie : « Sorti il y a 7 h », « NOUVEAU »).
- Panneau « Disponible » : un chapitre « non confirmé » n'est plus compté ni pris comme « dernier ».

# 2.3.20 — 9 novembre 2026

- Chapitre annoncé par UN seul site au-dessus d'au moins 3 autres sites de la même langue (Mythic Item Obtained « 195 » chez aquareader, la saison 2 finit au 194) : affiché « 1 site · non confirmé », jamais « NOUVEAU », aucune notification tant qu'un 2e site ne l'a pas ; anciennes notifications de ce type retirées au démarrage. Toutes langues, toutes œuvres.

# 2.3.19 — 9 novembre 2026

- Numérotation vérifiée par l'accord de toutes les sources, même règle pour chaque œuvre (`chapter_consensus.dart`) :
  - site dont toute la numérotation est décalée (son « 195 » a la date du 194 des autres) : mis de côté pour cette œuvre ;
  - numéro loin devant la moitié des sites (« 203 » quand ils s'arrêtent à 195), sans les chapitres intermédiaires sur ce site ni date de moins de 14 jours : non montré. Un site réellement en avance (196 … 203 tous listés) et les sorties anticipées de 1 à 3 chapitres restent ;
  - FR et EN jamais comparés entre eux ; moins de 3 sources : rien n'est retiré ;
  - chaque retrait est noté dans le journal (« Numérotation <œuvre> — <site> : … »).
- Tests : `test/v2319_consensus_test.dart`.

# 2.3.18 — 8 novembre 2026 — Chargement complet, étape 1

- Catalogues : 2 nouvelles méthodes de lecture — liste « charger plus » des thèmes Madara (500 séries par requête) et pages « liste A-Z » / « manga list ». Un catalogue de moins de 30 séries n'est plus considéré comme complet (le site reste cherché).
- Journal : pour chaque catalogue non lu, la raison exacte (« Catalogue non lu — site : API WordPress: HTTP 404 · liste Madara: … · plan du site : absent »).
- Nouvelle version = nouvel essai immédiat des catalogues ratés (plus d'attente de 6 h), chargement complet au 1er démarrage.
- Titres écrits un peu autrement retrouvés dans l'index (« The » en moins, « (Official) », « manhwa »…). Les listes de chapitres restent vérifiées contre les autres sources.
- Fiche : plus de « Recherche sur 152 sites » automatique. Œuvre hors bibliothèque : connecteurs intégrés + index ; bibliothèque : recherche silencieuse en fond ; bouton « Chercher d'autres sites » inchangé.
- « 289 chapitres » pour un dernier ch. 280 : affiché « 280 chapitres + 9 spéciaux » (ch. 0, demi-chapitres, annexes).
- Listes de 1 à 3 chapitres (mangabats / manganato) : page enregistrée dans `diagnostics\` pour ajouter la suite.

# 2.3.17 — 8 novembre 2026

- « En pause » toujours vide — cause trouvée grâce au journal 2.3.16 : AniList renvoyait bien les séries en pause (Vagabond, Hunter x Hunter, Omniscient Reader…), mais son champ « status » par défaut (version 1) les déclare « RELEASING ». Les requêtes demandent maintenant `status(version: 2)`, qui donne le vrai statut HIATUS (catalogue, recherche, animés).

# 2.3.16 — 8 novembre 2026

- Découvrir › Lectures par statut : le journal note, pour chaque onglet chargé, combien de séries AniList sont gardées ou déplacées, et pourquoi (titre, statut décidé, raison). Une erreur AniList est aussi notée (avant : ignorée en silence).
- Historique des sorties : un titre qui se réduit à moins de 3 caractères (titres en cyrillique, thaï…) n'est plus comparé.

# 2.3.15 — 8 novembre 2026

- Statut plus précis (I Killed the Main Player affiché « en pause » alors qu'il a repris) :
  - un chapitre sorti il y a moins de 30 jours (n'importe quelle source, une nouveauté vue par l'app, ou les flux « dernières sorties » des sites) remet la série « en cours », même si AniList dit encore pause / annulée ;
  - l'inactivité (pause > 100 j, annulée > 18 mois) n'est déduite que de la date du chapitre le PLUS RÉCENT ; s'il n'a pas de date, aucune pause n'est inventée.
  - Découvrir › Lectures par statut : le catalogue AniList est revérifié par ce moteur (une série « hiatus » qui a repris passe dans « En cours »).

# 2.3.14 — 8 novembre 2026

- solaris-scans.fr (journal 2.3.13 : 20 pages trouvées, refusé pour une icône 128×128 en page 20) : pour des pages lues dans les scripts, les petites images du site en début / fin de liste sont retirées et le chapitre reste lisible. Au milieu du chapitre, toujours refusé.
- rimuscan « 24828 » : le lecteur de listes générique collait les morceaux du lien (« Chapitre 248 » + « 28 oct »). Morceaux séparés. Diagnostic des listes absurdes déclenché sur la liste finale (toutes méthodes).
- Tests : `test/v2314_detection_test.dart`.

# 2.3.13 — 8 novembre 2026

- Chapitres « affichés en JavaScript » (solaris-scans.fr…) : les adresses des images sont cherchées dans les scripts / JSON de la page (Next.js, données en ligne) et lues par le lecteur Pazulu, sans navigateur. Images d'une même page payante / connexion / anti-robot jamais acceptées.
- Diagnostic : la page d'un chapitre encore illisible, ou d'une liste aux numéros absurdes (rimuscan « 24828 »), est enregistrée dans `diagnostics\` pour écrire le lecteur exact de ce site.
- Message clair : « la version FR existe sur <site>, mais ses pages ne sont pas encore lisibles ici » (au lieu de « pas de version FR »).
- Tests : `test/v2313_embedded_test.dart`.

# 2.3.12 — 8 novembre 2026

- « Lire en FR » ouvrait l'anglais (journal : Max-Level Newbie ch. 276 ouvert 3 fois sur mangaread EN) : la priorité à la langue choisie avait disparu du tri des lecteurs. Rétablie : un lecteur FR lisible passe avant tout lecteur EN, même hors ligne.
- Lecteur : les sites trouvés pendant la lecture sont ajoutés tout de suite au chapitre ouvert et aux suivants ; si le chapitre n'avait pas pu s'ouvrir, le nouveau lecteur est essayé automatiquement. Plus besoin de quitter et rouvrir.
- Numéros collés (« Chapter 272 » + « 28 Oct » lus « 27228 », TBATE « 2512 ») : le texte des liens est lu avec un espace entre ses morceaux.
- Découvrir › « Lectures par statut » : En cours (publication qui continue), En pause, Annulé (axed), Terminé — ta bibliothèque (moteur de statut) + tout le catalogue AniList filtré par statut, page après page.

# 2.3.11 — 8 novembre 2026

- Démarrage : chargement complet (jusqu'à 5 min la 1re fois) — catalogues de tous les sites, chapitres de TOUTES les œuvres de la bibliothèque depuis tous leurs sites, nouveautés, statut des séries. Ensuite : seules les listes de plus d'1 h sont relues (démarrages rapides) ; le reste continue en fond.
- Lecture fluide : pendant la lecture, les écrans derrière le lecteur ne se redessinent plus qu'au plus toutes les 3 s, les tâches de fond marquent une pause entre deux sites, l'index n'est pas réécrit. Index des catalogues (centaines de milliers de titres) : lecture, normalisation, tri et sauvegarde dans un fil séparé.
- Chapitres dès la 1re ouverture : une fiche ouverte se met à jour toute seule dès que la liste complète arrive ; la liste déjà connue reste affichée pendant le rechargement (plus de cases grises).
- Langue : choisir un lecteur EN pour UN chapitre (FR manquant) ne bascule plus toute l'œuvre en anglais. Si un lecteur échoue, les autres lecteurs de la même langue sont essayés avant l'autre langue. Message clair quand la langue choisie n'existe pas encore pour un chapitre.
- Moteur de statut (en cours / en pause / annulée / terminée) : AniList, MangaDex, statut écrit sur chaque site, puis date du dernier chapitre vu (plus de 100 jours = pause, plus de 18 mois = annulée). Les séries en pause, annulées ou terminées sortent du planning ; Découvrir › « Statut de mes séries » les range par catégorie. Statut affiché sur la fiche (avec la raison).
- Tests : `test/v2311_status_test.dart`, index (remplacement d'un site).

# 2.3.10 — 8 novembre 2026

- Listes « plusieurs œuvres mélangées » : rimuscan, manganato, mangabats, lelmanga étaient refusés à tort. Une liste n'est plus jugée mélangée que si aucun bloc de numéros ne contient la majorité des chapitres (une page d'accueil : 240, 877, 3862…). Une vraie liste partielle (1–3 puis 150–200) est acceptée.
- Un lien égaré d'une autre série (« ch. 3862 » dans une liste de 200) est retiré au lieu de faire refuser toute la liste (test v2.1.1 mis à jour en conséquence).
- AsuraScans : une série déplacée vers une adresse à suffixe aléatoire (/comics/solo-leveling-ab39de10) est suivie au lieu d'être refusée.

# 2.3.9 — 8 novembre 2026 — Index des catalogues de tous les sites

- Au démarrage (écran logo), Pazulu lit le catalogue complet de chaque site (liste de toutes ses séries : API WordPress des sites Madara, page « list-mode » des sites MangaThemesia, sinon plan du site). Métadonnées seulement, aucune image, aucune page de chapitre. Gardé sur disque, rafraîchi toutes les 24 h, le reste en fond.
- Chaque œuvre (bibliothèque, Découvrir, recherche) reçoit d'un coup TOUS les sites qui la listent : plus de recherche site par site, aucune source avant une autre. La recherche « 208 sites » ne concerne plus que les sites dont le catalogue n'a pas pu être lu.
- Découvrir : section « Tous les titres » (toutes les œuvres de tous les catalogues, A → Z, filtre instantané, nombre de sites par œuvre). Une recherche filtre aussi cet index immédiatement.
- Tests : `test/v239_site_index_test.dart`.

# 2.3.8 — 8 novembre 2026

- Correctif grave (journal 2.3.7) : SushiScan a été détaché de Solo Leveling (« plusieurs œuvres mélangées ») et 6 copies hors ligne supprimées, à cause du ch. 0 placé avant 179.5–200. Les connecteurs intégrés (MangaDex, SushiScan) lisent une série par identifiant : ce contrôle ne s'applique plus qu'aux sites web ; le ch. 0 / prologue n'est plus compté comme une autre œuvre. MangaDex n'est plus refusé pour One Piece.
- Copies hors ligne : écritures de l'index une par une (erreur « Cannot delete file index.json » lors de suppressions simultanées).
- Recherche sur tous les sites : un site trouvé est utilisable tout de suite (la fiche se recharge sans attendre les 200 autres). Le bandeau flottant qui couvrait les chapitres est retiré : progression dans le panneau « Disponible ».
- Tests : `test/v238_guard_test.dart`.

# 2.3.7 — 8 novembre 2026

- Chargement au démarrage (écran logo) : à la première ouverture, ou après plus de 3 h d'absence, les sorties et les listes de chapitres de la bibliothèque sont mises à jour une fois (max 150 s la 1re fois, 60 s ensuite). Sinon démarrage immédiat ; le reste se met à jour en fond.
- Recherche sur les 200+ sites : faite une fois par œuvre, puis gardée sur disque (nouvelle recherche après 1 jour s'il manque une langue ou des sites, sinon 3 jours). Plus de « 207 sources » à chaque ouverture de fiche. « Chercher d'autres sites » reste immédiat.
- Listes de chapitres gardées sur disque pour toute œuvre visitée : retour sur une fiche instantané.
- Couvertures : en-têtes attendus par les sites (Referer) et nouvel essai automatique après un échec.

# 2.3.6 — 8 novembre 2026

- Copies hors ligne : une copie d'un chapitre lu en ligne (séparateurs, crédits répétés, tranches webtoon) n'est plus jugée « incomplète » puis supprimée et retéléchargée à chaque ouverture (journal 2.3.5 : boucle sur Necromancer 319/307, Frozen Player 160, Dress-Up Darling 116). Cause probable des saccades.
- « Lire en FR » : un lecteur FR lisible passe toujours avant l'EN, même hors ligne. Le choix est aussi gardé pour les œuvres hors bibliothèque.
- Langue : un chapitre qu'un site liste en FR compte comme FR (filtre, badge, lecteurs). Seule la notification attend une 2e source.
- Sorties : un chapitre qu'une autre source avait déjà n'est plus « nouveau » ; série terminée/annulée : pas de nouveauté sans date ; anciennes notifications de ce type retirées.
- Sources : recherche automatique sur tous les sites quand une langue n'a aucun chapitre ou que moins de 3 sites ont l'œuvre ; sites trouvés gardés après redémarrage ; redirections http:// reprises en https:// (mangahere, mangatown…) ; recherche bloquante ramenée de 120 à 45 s.
- Dates : SushiScan lit la date de chaque chapitre.
- Fiche : panneau « Disponible » lisible (par langue : nombre, dernier chapitre, sites), progression de la recherche ; fond moins chargé.
- Écran de démarrage avec logo et étape en cours.
- Tests : `test/v236_fixes_test.dart`.

# 2.3.5 — 8 novembre 2026

- Écran noir : le journal 2.3.4 montre une copie hors ligne incomplète juste avant chaque relance. La copie est maintenant supprimée et le chapitre lu en ligne, dans les deux chemins du lecteur. Les commandes ne se masquent qu'après l'affichage réel d'une page ; chargement visible (« Page 1… ») ; images très hautes limitées à 16 000 px (limite des cartes graphiques) ; journal détaillé de chaque ouverture.
- Langue : « Lire en : Auto · EN · FR » sur la fiche (mémorisé). Lecteur : panneau avec tous les lecteurs visibles, rangés par langue, choix de la langue en un clic.
- Détection FR/EN : un chapitre qu'un seul site annonce en FR, en avance sur toutes les autres sources FR alors que l'EN existe, s'affiche « FR ? », n'entre pas dans le filtre FR et n'est pas notifié tant qu'une deuxième source FR ne le confirme pas. Les anciennes notifications de ce type sont retirées au démarrage.
- Recherche des lecteurs avec tous les titres alternatifs (ex. « Disastrous Necromancer »).
- Découvrir : une seule liste pour toutes les sources (connecteurs et sites, doublons fusionnés), un seul compteur.
- Onglet « Sorties » retiré. Accueil : sorties regroupées par œuvre et langue (« Ch. 226 → 229 »).
- Planning : lignes type programme TV, heures en grand, séries suivies en premier, 8 par heure puis « Voir plus ».
- Tests : `test/v235_language_test.dart`.

# 2.3.4 — 8 novembre 2026 — Vraie cause de l'écran noir (journal)

- **Écran noir corrigé à la source** : le journal `pazulu.log` montrait « Bad state: Cannot clone a disposed image » au moment des écrans noirs. Cause : l'image de couverture (`CoverImage`) gardait l'ancienne image dans une animation de fondu alors que Flutter l'avait déjà libérée ; quand la couverture se reconstruisait (retour sur une fiche, filtre « Non lus », changement de taille), le dessin de toute la fenêtre plantait. Le fondu ne garde plus d'ancienne image ; la taille de décodage avance par paliers de 120 px.
- **Copies hors ligne incomplètes** (ex. Catastrophic Necromancer 318/319 sur mangaread.org) : supprimées automatiquement et le chapitre est lu en ligne, au lieu d'échouer à chaque ouverture.
- **Sources bloquées** : menu sur chaque source de la fiche d'une œuvre, « Bloquer … » (mauvaise langue, mauvaise qualité). La source n'est plus jamais utilisée (recherche, chapitres, lecture, nouveautés, planning) ; liste et déblocage dans Réglages › Moteur Pazulu.
- **Faux FR** : les chapitres FR 226–229 de Return of the Frozen Player et 301–307 de Catastrophic Necromancer viennent de lelmanga.com, qui les publie le 7/11 en se présentant comme « VF ». S'ils sont en réalité en anglais, bloquer lelmanga.com les retire partout.
- Journal : la sauvegarde de `connector-health.json` ne se chevauche plus (erreurs « Cannot copy file … .bak » en boucle).
- (2.3.3) Navigateur caché WebView2 désactivé par défaut.

# 2.3.3 — 8 novembre 2026 — Navigateur caché désactivé par défaut

- **Écran noir** : la fenêtre WebView2 cachée (utilisée pour les chapitres affichés seulement en JavaScript) est désactivée par défaut. Sur Windows c'est une vraie fenêtre posée au-dessus de l'application ; même réduite, elle pouvait recouvrir tout l'écran. Ces chapitres passent maintenant automatiquement sur un autre lecteur. Réactivable dans Réglages › Moteur Pazulu › « Lecture via navigateur caché (expérimental) ».

# 2.3.2 — 7 novembre 2026 — Écran noir, faux chapitres FR, lecteur plus lisible

- **Écran noir à l'ouverture de certains chapitres** : ces chapitres passent par la WebView2 cachée (pages chargées en JavaScript). Sur Windows c'est une fenêtre native posée au-dessus de l'app ; si elle n'était pas masquée à temps, elle recouvrait tout en noir. Elle est maintenant enfermée dans un carré d'1 pixel : elle ne peut plus rien recouvrir. Échap fonctionne aussi dans ce mode.
- **Plus jamais d'écran vide** : un élément qui plante affiche un message lisible à sa place au lieu d'un écran noir ou gris, le reste de l'app reste utilisable.
- **Faux chapitres FR** : les chapitres premium, VIP, « accès anticipé », « bientôt disponible », à débloquer avec des pièces ou datés dans le futur ne sont plus comptés comme sortis (pour tous les sites). Les notifications d'un chapitre qu'aucune source ne propose plus dans cette langue sont retirées.
- **Lecteur plus propre** : la liste des lecteurs ne flotte plus par-dessus la page ; un bouton « Lecteur 1/3 · EN » ouvre un panneau (touche L). Les commandes se masquent seules 2,5 s après l'affichage des pages (un clic les fait revenir). En mode vertical, la première et la dernière page ne sont plus cachées sous les barres.
- Tests : `test/v232_reader_lang_test.dart`.

# 2.3.1 — 7 novembre 2026 — Toutes les sources au même niveau

- **Plus aucune source de référence** : MangaDex n'est plus « la » source. Chaque liste de chapitres (MangaDex comme n'importe quel site) est comparée à ce que disent TOUTES les autres sources ; une liste n'est refusée que si elle contredit ses pairs (autre série, page d'accueil mélangée), jamais parce qu'elle a plus de chapitres. Les notifications appliquent la même règle à toutes les sources.
- **Recherche sur toutes les sources en même temps** : à l'ouverture d'une œuvre, connecteurs et sites du répertoire sont interrogés ensemble (plus d'attente de 20 s sur les connecteurs seuls), puis toutes les 24 h pour la bibliothèque (12 h pour les autres œuvres).
- **Si les sources liées échouent ou n'ont rien en EN/FR** (ex. MangaDex « Connection closed », œuvre sans chapitre dans vos langues) : la recherche sur tous les sites se fait tout de suite, avec la progression, et la liste se reconstruit avec ce qui est trouvé, au lieu d'afficher une erreur.
- **MangaDex** : connexion interrompue, délai dépassé et 502/503/504 réessayés deux fois.
- **Dates de sortie des chapitres** : lues aussi sur les sites (Madara, MangaThemesia…). Chaque chapitre affiche « Sorti il y a 3 h » ou « Sorti le 6 mai 2026 · il y a 6 mois », avec un badge NOUVEAU la première semaine.
- **Planning redessiné** : journée en frise horaire (un bloc par heure, repère « Maintenant »), cartes avec couverture, chapitre ou épisode, « sorti il y a… » ou « dans… », plateformes ; résumé du jour (sorties, animés, chapitres, déjà sorties, de ma liste).
- **Fiche d'œuvre** : les sources qui fournissent des chapitres sont affichées directement (nom et nombre de chapitres) ; le bloc vide « Sources liées » est retiré (« Lier un site à la main » est dans le menu Sources) ; bouton « Chercher sur tous les sites » sur une liste vide ou en erreur.
- Corrections : 2 tests échoués de la 2.3.0 (nombre de tentatives HTTP, heure dans le titre d'un lien Madara) et avertissements de l'analyseur.
- Tests : `test/v231_peer_sources_test.dart`.

# 2.3.0 — 7 novembre 2026 — Planning de la semaine, chapitres complets, Profil

- **Planning de la semaine (tout le monde)** : jour par jour et heure par heure, TOUTES les sorties de la semaine. Animés : chaque diffusion AniList (heure exacte, plateformes de simulcast). Lectures EN et FR : chaque chapitre MangaDex, le calendrier officiel WEBTOON EN et FR, et le bloc « dernières mises à jour » de chaque site du répertoire. Les jours à venir sont estimés d'après le rythme réel de chaque série (« vers 17:00 »). Navigation semaine précédente / suivante, recherche, filtres Lectures / Animés / EN / FR, rapport des sources (une source cassée ne vide jamais le planning).
- **« Ma liste »** : le même planning limité à vos séries (bibliothèque), avec pauses, hiatus, reprises et nouvelles saisons.
- **Partie animés du planning** : présente pour toutes les diffusions de la semaine, plus seulement celles de la bibliothèque.
- **Sorties confirmées corrigées** : la date affichée est la vraie date de publication. Un chapitre de 2023 n'est plus « sorti il y a 42 min ». Les rafales d'anciens chapitres et les numéros impossibles (ch. 3861 dans Solo Leveling) sont refusés à la détection et retirés des anciennes notifications ; le « dernier chapitre connu » est réparé.
- **Chapitres manquants, pour toutes les œuvres** : une liste avec des trous (ex. 198 → 262) ou plus courte que le dernier chapitre annoncé déclenche tout de suite une recherche sur tous les sites. Au démarrage, toute la bibliothèque est vérifiée et complétée en arrière-plan. Un site qui propose une liste complète et continue (1 → 330) est accepté même si MangaDex s'arrête plus tôt ; sur un site, plusieurs fiches au même titre sont vérifiées et la plus complète est gardée.
- **Sources plus robustes** : erreurs 502/503/504 retentées deux fois avec attente, mise en pause plus courte (20 s, 5 min max), « Réessayer » relance immédiatement les sources en pause (sauf limite 429 imposée par le site).
- **Découvrir rapide** : la fusion des résultats ne compare plus chaque œuvre à toutes les autres (le gel venait de là) ; mises à jour regroupées ; catalogues des sites gardés sur disque et affichés instantanément, rafraîchis toutes les 6 h ; « Voir plus » au lieu de milliers de cartes.
- **Découvrir par catégories** : catalogue avec métadonnées (note, nombre de chapitres, statut), tri Tendances / Populaires / Mieux notés / Nouveautés, Manga / Manhwa / Manhua, 16 genres. À l'ouverture, Pazulu retrouve l'œuvre sur les connecteurs et cherche ses lecteurs sur tous les sites.
- **Profil** : niveau et expérience (chapitres, épisodes, séries terminées, favoris), série de jours, statistiques « depuis le début » et « mon année » (heures estimées, activité par mois, genres préférés, œuvre la plus suivie), 20 succès avec progression et notification au déblocage.
- Tests : `test/v23_planning_sources_test.dart`.

# 2.2.0 — 6 novembre 2026 — Animés, planning à l'heure, nouvelle interface

- **Chargement des sources une seule fois** : la liste des chapitres s'affiche instantanément depuis la mémoire (copie sur disque par œuvre), puis se rafraîchit seule en arrière-plan. La recherche sur tous les sites n'est relancée qu'une fois par semaine pour une œuvre suivie, sans barre de progression (sauf si vous la demandez).
- **Chapitres parasites (Solo Leveling, ch. 3861)** : la cause était une copie hors ligne issue d'un site web incohérent, traitée comme source de confiance. Les copies des sites web sont désormais revérifiées, et supprimées si elles n'appartiennent pas à l'œuvre (progression réparée). Rattachement d'un site seulement si le titre de SA fiche confirme l'œuvre (« Solo Leveling: Ragnarok » ≠ « Solo Leveling »).
- **Animés** : recherche et tendances dans Découvrir (mode « Animés »), fiche animé avec bannière, statut, saison, studio, prochain épisode avec compte à rebours et heure locale, épisodes vus (+/−), saisons liées et boutons « Où regarder » vers les plateformes officielles (Crunchyroll, ADN, Netflix… selon AniList). Pazulu ne lit ni n'extrait aucune vidéo et ne contourne aucun DRM : les épisodes s'ouvrent chez l'éditeur, dans votre navigateur.
- **Planning** : filtres Tout / Lectures / Animés et EN / FR ; vue des 3 prochaines semaines jour par jour avec l'heure (exacte pour les animés, « vers HH:MM » quand une œuvre sort toujours à la même heure) ; section « Pauses, hiatus, reprises et nouvelles saisons » (pause probable, hiatus détecté ou annoncé, reprise après une longue pause, nouvelle saison annoncée).
- **Interface** : nouvelle palette indigo plus sobre (surfaces pleines, contraste AA), rail de navigation épuré, fiche d'œuvre avec un seul bouton principal « Reprendre · Ch. N » et un menu « Sources », lignes de chapitre à colonne de numéros. Choix appuyés sur le skill UI UX Pro Max (voir `docs/design-system/MASTER.md`).
- **Lecteur maison** : barres flottantes qui glissent, liste des chapitres (C), réglages de lecture (S : sens, ajustement, double page, largeur du webtoon, fond noir / graphite / sépia), ligne de progression discrète quand l'interface est masquée, curseur de pages dans le sens de lecture.
- Avertissements de l'analyseur retirés (code inutilisé).
- Tests : `test/anime_planning_v22_test.dart` (AniList, planning animé, heure habituelle, confirmation de titre, mémoire des chapitres, compte à rebours).

# 2.1.1 — 6 novembre 2026 — Correctif : chapitres d'autres œuvres

- Bug grave corrigé : un site qui redirigeait la fiche vers sa page d'accueil faisait apparaître les derniers chapitres de TOUTES ses séries dans l'œuvre (ex. Solo Leveling avec des chapitres 3862, 877, 240).
- Nouveaux garde-fous (`ListingGuard`) : fiche reçue = fiche demandée (pas de redirection vers l'accueil ou une autre série) ; chapitres appartenant à l'URL de l'œuvre (« solo-leveling-ragnarok » ≠ « solo-leveling ») ; liste aux numéros dispersés refusée ; numéros incompatibles avec les chapitres de confiance (MangaDex, copies locales) refusés ; lien de résultat de recherche cohérent avec son titre.
- Réparation automatique : à chaque ouverture, les sites rattachés automatiquement sont revérifiés ; un site incohérent est détaché (lien, chapitres, dernier numéro connu et fausses notifications retirés).
- Tests : `test/listing_guard_v211_test.dart` reproduit le cas Solo Leveling.

# 2.1.0 — 6 novembre 2026 — Toutes les sources, Planning

- Recherche : TOUS les sites du répertoire sont interrogés à chaque recherche (plus de sélection), dix à la fois, résultats affichés au fil de l'eau avec la progression et un rapport par site.
- Connecteur universel des sites web : détection automatique Madara / MangaThemesia (ts_reader) / lecteurs génériques pour la recherche, les fiches, la liste des chapitres (y compris la liste Madara chargée en AJAX) et les PAGES. Les chapitres des sites ne sont plus de simples liens externes : ils s'ouvrent dans le lecteur Pazulu après validation des images, avec rendu WebView2 invisible si nécessaire.
- Changement de domaine d'un site suivi et mémorisé (DNS public uniquement).
- Lecteurs supplémentaires : à l'ouverture d'une œuvre, recherche en arrière-plan du même titre sur tous les sites (une fois toutes les 6 h), rattachement automatique sur alias exact, rechargement de la liste des chapitres. Bouton « Chercher sur tous les sites » sur un chapitre réduit à un lien externe (ex. Webnovel).
- Découvrir : « Populaires » + « Sur tous les sites », rempli depuis la page d'accueil de chaque site.
- Nouvel onglet Planning : sorties EN/FR confirmées (14 jours) et prochaines sorties estimées d'après le rythme réel de chaque œuvre et de chaque langue ; « Mes lectures » avec jours de lecture et objectif par œuvre.
- Test corrigé (identifiants de source identiques dans le test de fusion), imports inutilisés retirés.

# 2.0.0 — 6 novembre 2026 — Pazulu Source Engine 2.0

- Nouveau moteur `lib/engine/` : disponibilité ≠ pages ≠ pages validées ; HTTP sûr ; validation d'images réelle ; circuit breaker ; Smart Source Router ; découverte multisource prudente ; diagnostics.
- `ChapterKey` : extras, bonus de volume et décimales exactes ne sont plus fusionnés.
- SushiScan : lecture de la liste `ts_reader` du HTML public (14/14 pages sans WebView) ; WebView2 invisible seulement si nécessaire, avec détection des pages de restriction.
- MangaDex : respect de `Retry-After` sur HTTP 429.
- Extensions v2 (`.pazulusource` / `.pazulupack`), 7 manifestes intégrés (3 natifs, 4 profils HTML désactivés tant qu'ils ne sont pas testés).
- Lecteur : sélecteur Lecteur 1/2/3, recherche d'autres sources, confirmation d'édition, panneau d'étapes, double page, ajustement, sens par œuvre, cache CBZ après affichage.
- Réglages : section Moteur Pazulu (basculement automatique, autre langue, Extensions, Diagnostic).
- Tests : 5 nouveaux fichiers + fixtures HTML. Compilation et exécution des tests **non effectuées** dans l'environnement de création.

# 0.5.3 — 6 novembre 2026

- SushiScan : un chapitre annonce comme 14 pages ne peut plus etre valide comme 1/1.
- Lecture native : analyse systematique du DOM rendu, detection des selecteurs page par page, navigation ordonnee et confirmation de chaque image.
- WebView2 invisible en preparation ; les pages resolues sont ensuite affichees dans le lecteur Pazulu.
- Journalisation des echecs de pagination et pas de progression sauvegardee sur un chapitre incomplet.
- Tests Dart avec fixture 14 pages et simulation du script JavaScript avec 14 transitions.
- Validation site reel/compilation Windows non effectuees dans cet environnement.

# V0.4.21 — Catalogue Keiyoushi et édition liée (Windows)

- Serveur Suwayomi officiel conservé, pas de fork du moteur.
- Catalogue paginé FR/EN exposé dans Pazulu Extensions, installation/mise à jour par commande officielle avec confirmation utilisateur.
- Diagnostic installé : titre exact et nombre réel de chapitres, sans images téléchargées.
- Association manuelle d’une édition d'extension à une œuvre et persistance du lien sans réinitialisation des progrès.
- Outils Windows : diagnostic GraphQL réel avec rapport JSON, comparaison statique des 209 sites à un checkout Keiyoushi et patch expérimental Scan-Manga limité à la détection de liens publics.
- Scripts de compilation : Windows seulement (pas de construction ni d'installation Android).
- Tests ajoutés (mocks GraphQL) : pagination, filtre FR/EN, installation/mise à jour explicites, validation des identifiants.
- Limites : pas de compilation Flutter dans cet environnement, pas de preuve de chargement d'image ni de correctif validé pour Scan-Manga.

## 0.4.18 - Diagnostic réel du moteur d’extensions

- Recontrôle forcé du moteur Suwayomi à la demande de nouveaux lecteurs.
- Le cache de recherche et de chapitres est invalidé uniquement lorsque la liste d’extensions change ; aucun historique de lecture n’est supprimé.
- Le bouton de recherche explique si Suwayomi est absent ou n’expose aucune extension FR/EN.
- La fiche distingue explicitement un catalogue partiel de chapitres lisibles.
- Ajout de Diagnostiquer-Sources.cmd : test GraphQL local et recherche de Solo Leveling dans les extensions installées (sans téléchargement d’images).
- Aucun statut « 209 lecteurs fonctionnels » : les domaines non testés restent de simples adresses.

## 0.4.17 — Passerelle multi-extensions locale (expérimentale)

- Brancher les sources Suwayomi réellement installées aux recherches et aux chapitres Pazulu.
- Métadonnées sans téléchargements ; requête de pages au clic Lire ; cache natif du lecteur.
- Ne plus afficher « 2 connecteurs » en dur : afficher le nombre réellement connecté.
- Sécuriser les URL du proxy local des images ; maintenir le thème et les sauvegardes.
- Tests GraphQL simulés inclus, build Windows non exécuté.

## 0.4.16 — Découverte web opt-in et rapport par source

- Recherche multi-source par fiches publiques : sites choisis par l'utilisateur
  depuis Découvrir (maximum 12, quatre requêtes simultanées), sans
  télécharger de chapitre ni masquer les erreurs réseau.
- Connecteur générique de métadonnées WordPress/Madara, avec résultats
  strictement filtrés par titre et URL sur le site sélectionné.
- Lorsqu'une fiche publique est trouvée, son index de chapitres peut être
  inspecté en lecture seule ; les liens restent externes. Aucune extraction
  d'image ni accès premium n'est fourni par ce connecteur.
- Les fiches provenant du web sont identifiées visiblement comme telles.
- Le moteur des lecteurs natifs n'interroge pas ces adaptateurs expérimentaux
  lors de sa recherche automatique de pages : une URL web n'est jamais
  présentée comme un lecteur Pazulu opérationnel.
- Conservation de la DA, du lecteur local, des 200 adresses et des sauvegardes.

## 0.4.15 — Repertoire de 200 domaines directement accessible

- Les 200 adresses deja fournies par l'utilisateur ne sont plus cantonnees a un ecran de suggestions : elles alimentent le gestionnaire Sources, sans ajout manuel. Quatre doublons avec le repertoire original sont fusionnes ; 196 nouvelles adresses sont ajoutees aux 13 sources initiales (209 entrees initiales + annuaire, avant comptes personnels).
- Recherche de sites, filtres FR/EN, sources initiales, annuaire et sources personnelles ; chargement paresseux des lignes pour eviter d'instancier 200 cartes d'un coup.
- Aucun changement du lecteur, du theme, des animations, du suivi local ou des sauvegardes. Les identifiants du repertoire sont stables.
- Surveillance reseau automatique limitee aux 13 sites initiaux et aux sites ajoutes personnellement. Chaque adresse du repertoire se teste individuellement depuis son menu ; aucun balayage brutal de 200 domaines.
- Le repertoire est une liste de sites, pas 200 connecteurs natifs. Recherche et recuperation natives : uniquement les moteurs effectivement implementes (MangaDex et Pepper&Carrot). La lecture des autres sites reste a valider selon leurs conditions et leur structure.
- Test de correspondance de catalogue et de doublons ajoute dans `test/community_sources_v0415_test.dart`. La compilation Flutter necessite toujours une verification sur Windows.

## 0.4.14 — Fiche claire et moteur de sources plus fiable

- Fiche d'œuvre réagencée, états de disponibilité compacts, diagnostics et tags repliables.
- Choix des versions simplifié et hiérarchie cache local > vrai connecteur > lien externe.
- Rétrogradation temporaire du chapitre en échec, repli automatique vers un autre lecteur natif quand disponible.
- Meilleure reconnaissance du même comic entre manga/manhwa/webtoon et listes de chapitres HTML avec options.
- Les liens d'éditeur ne constituent plus un chapitre lu ; import manuel retiré du dialogue principal.
- Tests ajoutés pour sélection de source, rapprochement intersources et listes de chapitres.
- Limite : les 13 sites du catalogue ne sont pas des connecteurs de lecture confirmés.

## 0.4.13 — 5 novembre 2026

- Choix de toutes les versions d'un chapitre via « Voir les N versions », avec distinction lecteur natif / lien externe (éditeur, accès parfois payant ou expiré).
- Correction : les chapitres externes MangaDex ne sont plus traités comme des images locales (évite les faux 404 at-home) ; erreur 404 native désormais explicite.
- Confirmation avant ouverture d'un chapitre externe, toujours dans une seule fenêtre. Le lecteur ne simule plus un chapitre officiel 1/1 lorsqu'il ne possède aucune image.
- Catalogue consultable de 200 sites proposés par l'utilisateur, filtrables par langue, statut ancien et nom, ajout individuel sans compilation. Aucun nouveau connecteur de pages annoncé comme opérationnel.
- Direction artistique inchangée. Seules les vues de sélection et les textes d'erreur changent.

## 0.4.12 — Audit de couverture des chapitres (5 novembre 2026)

- Rafraîchissement des catalogues toutes les 20 minutes (ou manuellement), au lieu de garder indéfiniment des listes en mémoire.
- État visible de chaque catalogue : confirmé, vide, indisponible ou lecteur officiel ; le nombre de chapitres n'est jamais présenté comme le total publié.
- Si un catalogue tombe en panne, conservation des anciennes entrées en mode « à revérifier » au lieu de les effacer et de prétendre qu'elles sont à jour.
- Les fiches de sites que l'utilisateur a reliées à une œuvre peuvent contribuer leur liste HTML publique au regroupement FR/EN, uniquement si le site est compatible. Ces entrées restent des liens de lecture, pas des images utilisables dans le lecteur maison.
- Aucune récupération de pages à la recherche ; pas de contournement de comptes, DRM ou restrictions de sites.
- Nouvelle suite de tests de fusion des sources et d'audit de disponibilité.
- Thèmes, navigation, composants graphiques existants et lecteur maison inchangés. Compilation Windows et tests Flutter à confirmer sur le PC utilisateur.

## 0.4.11 — Inventaire fiable et recherche d'autres lecteurs (5 novembre 2026)

- Plus de faux badges « chapitres manquants » issus d'un catalogue partiel.
- Statistiques fiables des entrées par langue, lecteurs natifs et liens officiels.
- Recherche native explicite avec correspondances de titres strictes et vérification des chapitres réellement lisibles.
- Chargement parallèle et coalescence des appels pour réduire le ralentissement lors de la navigation.
- Import CBZ déplacé vers le menu secondaire ; DA conservée.
- Tests ajoutés et limitations documentées.

## 0.4.10 — correctif de compilation Windows (5 novembre 2026)

- Correction des signatures Dart `listChapters` et `latestChapters` de `PepperCarrotSource` (virgule incorrecte apres les parametres nommes), qui bloquaient `flutter analyze`, les tests Flutter et le build Windows.
- Aucune modification du moteur de lecture, des profils de sources, de la bibliotheque, des sauvegardes ou de la direction artistique.
- Verifications statiques locales et archive ZIP controlees. La compilation et les tests Flutter necessitent encore une execution sur Windows.

## 0.4.10 — 5 novembre 2026

- Separation claire entre recherche metadata / fiches et telechargement des pages seulement au clic sur Lire.
- Cache CBZ automatique par chapitre dans le lecteur natif (activable/désactivable dans Reglages ; active par defaut pour anciennes sauvegardes).
- Progression de recuperation affichee dans le HUD ; fallback reseau en cas d'erreur de cache.
- Telechargements simultanes du meme chapitre dedoublonnes ; garde HTTP/images (pas de HTML/Cloudflare pris pour une page), limites de taille et noms de fichiers sans collision.
- Nouveau connecteur public Pepper&Carrot FR/EN a partir de l'API documentaire de l'auteur ; moteur de recherche multi-connecteur resistant aux pannes et fusion conservatrice des doublons exacts.
- 13 sources historiques conservees sans les annoncer comme toutes compatibles ; aucune nouvelle extraction non autorisee.
- L'import CBZ reste facultatif, non plus le parcours principal.
- Themes, DA, animations, shell, lecteur et sauvegardes conserves ; seul le chargement du lecteur et des libelles de lecture a evolue.
- Tests ajoutes pour les requetes paresseuses, le cache, les pages HTML rejetees, les preferences et les chapitres FR/EN Pepper&Carrot (execution a valider avec Flutter).

## 0.4.9 — correctif compilation Windows (+16) — 5 novembre 2026

- Corrige `lib/ui/work_page.dart` : un clic sur une ligne de chapitre fournit
  `null` (aucun lecteur choisi), et les puces de lecteur fournissent un
  `SourceChapter`. Avant ce correctif, deux accès directs à `v.isExternal`
  et `v.externalUrl` empêchaient toute compilation sous Dart null-safety.
- La ligne sélectionne désormais le lecteur préféré si disponible ; les
  liens externes restent dans le parcours de reprise native, sans ouvrir
  automatiquement de deuxième fenêtre ni remplacer le HUD Pazulu.
- Aucun changement de thème, mise en page, animation, stockage ou connecteur.
- Compilation Windows et tests Flutter à valider sur le PC utilisateur.

## 0.4.9 — 5 novembre 2026

- Reprise native depuis Sorties : priorite aux chapitres lisibles dans ReaderPage
  (MangaDex, capture de session, archives CBZ). Pas de WebView ouverte
  automatiquement depuis le bouton Lire.
- Nouveau chemin d'import de CBZ/ZIP dans une oeuvre existante, avec FR/EN et
  numero canonique : la progression et les statuts sont partages entre sources.
- Le moteur DOM experimental demande maintenant la fiche destination, le numero
  et la langue avant d'enregistrer/lire les pages d'une session.
- Regroupement des variantes FR/EN d'un meme chapitre et reprise sur la plus
  proche position lorsque le lecteur precedent a disparu.
- Decompte dedoublonne par oeuvre et cle de chapitre pour les flux verifies.
- Lecture d'archives : verification de tailles/structure ZIP avant extraction,
  normalisation des images et conservation des archives sources.
- Tests sur l'identite, la reprise entre sources et l'import des CBZ dans une
  meme bibliotheque (a lancer sur Windows : Flutter absent ici).
- Theme Indigo, cinq onglets, palettes, fonds, animations et HUD lecteur conserves.
- **Attention** : les 13 domaines ne sont PAS encore tous des connecteurs
  auto-valides ; DOM experimental et permissions propres a chaque site.

## 0.4.8 — 5 novembre 2026

- Ecran Sorties repense avec le skill officiel UI UX Pro Max 2.15.0 : recherche UX "status alerts color contrast empty states" et Flutter "compact status cards responsive layout" executee.
- Entete structure, 4 compteurs, cartes par oeuvre avec couvertures, etats clairs par langue/source, actions visibles et etat vide compact.
- Theme et palettes intacts ; aucun changement du lecteur, du shell, de la surveillance ou des formats de sauvegarde.
- Responsive via LayoutBuilder, etiquettes d'etat en texte et icones, couleurs semantiques issues de la palette, pas d'animation de fond supplementaire.
- Test UI et statut ajoute. Compilation/test Flutter a valider sur Windows.

## 0.4.7 — 5 novembre 2026

- Bilan de verification reel par oeuvre, source et langue dans l'ecran Sorties : nombre de flux confirmes, echec, chapitres non lus et dernier numero.
- Chapitres disponibles non lus visibles des le premier controle, independamment des notifications de **nouvelles** publications.
- Decompte des chapitres non lus a partir de la progression et des chapitres lus, avec dedoublonnage et exclusion des anciens chapitres deja depasses.
- 1 clic pour associer l'URL de la page courante depuis le navigateur embarque a une oeuvre en bibliotheque ; aucun navigateur externe installe necessaire.
- Les erreurs de fiche, acces restreints et limites de controle sont visibles ; seuls les flux ayant fourni des chapitres sont comptes comme confirmes.
- Tests `test/release_scan_v047_test.dart` ; documents `docs/VALIDATION_0.4.7.md`.
- DA/animations/navigation/lecteur maison conserves ; aucune nouvelle prise en charge automatique des 12 autres sources en l'absence de liens de fiche.
- Validation Windows et Android a realiser ; aucun `flutter test`/build executable dans cet environnement.

## 0.4.6 — 5 novembre 2026

- Surveillance additive des **liens de fiches d'oeuvres** sur les sources compatibles en HTML public, sans crawler general ni telechargement de pages ; MangaDex conserve son connecteur natif.
- Nouveautes : detection FR/EN, premiere observation silencieuse, suivi par oeuvre/site/lien/langue, aucun doublon de chapitre, controle manuel et automatique limite par domaine/temps.
- Notifications avec lien et site permettant d'ouvrir directement la publication dans la fenetre unique ; anciennes sauvegardes compatibles (champs facultatifs).
- Sites officiels, protegés et pages JavaScript non verifies plutot que fausses confirmations. Erreurs HTTP, blocage ou liste non detectable explicitement affiches.
- Premier lien de fiche active la surveillance de l'oeuvre, qui reste desactivable.
- `html` 0.15.7 pour parser les pages HTML5, tests `test/chapter_listing_v046_test.dart`.
- DA : fichiers de theme, HUD, navigation, animations et composants graphiques **strictement inchanges** par rapport a 0.4.5.
- Compilation Flutter/Windows/Android non executee dans l'environnement de preparation ; validation reelle necessaire.

## 0.4.5 — 5 novembre 2026

- Stabilisation de la navigation rapide : chargement paresseux des onglets,
  TickerMode inactif pour tous les ecrans masques, aucun changement de style.
  Conservation des positions de defilement, filtres, recherches et Etats des
  ecrans deja visites ; pas de nouvelles fenetres.
- Trace de diagnostic apres 10 bascules d'onglets ; test de regression
  simulant 40 transitions et verifiant que les onglets restent montes.
- Sources personnelles : modification URL, nom et FR/EN avec maintien de
  l'identifiant, confirmation sur changement de domaine, invalidation de la
  disponibilite historique du domaine precedent ; pas de reecriture des
  anciens liens des livres ni de perte de lecture.
- Protection contre un controle reseau en cours qui reviendrait apres un
  changement de domaine et appliquerait un statut perime.
- Validation Windows reelle a faire : le type exact de crash n'est pas connu
  sans diagnostic Windows ; ne pas considerer le correctif confirme avant test.

## 0.4.4 — 5 novembre 2026

- Liste active de 13 sources ; ManhuaFast et ManhwaClan archivees sans supprimer les liens historiques.
- Formulaire dans Sources : une URL HTTPS, nom facultatif, choix FR et/ou EN, sans recompilation.
- Gestion des sources personnelles activees ou desactivees (donnees conservees) ; fichier autonome versionne avec sauvegarde .bak.
- Controles HTTP/TLS de disponibilite (application active) : evaluation raisonnee des erreurs, statut de fermeture supposee uniquement apres au moins 3 echecs sur au moins 24 h ; blocages 403/429 et redirections isoles.
- Bilan et verification manuelle dans la liste des sources ; le moteur commun de V0.4.3 sert aux sites personnalises.
- Tests unitaires de validation des URLs, stockage, statut 525, 403/429, redirections, puis retour a la normale.
- Fichiers de palette, navigation et composants visuels conserves a l'identique.
- Compilation Flutter toujours a confirmer sur Windows ; voir `docs/SOURCES_0.4.4.md`.

## 0.4.3 — 5 novembre 2026

- Ajout de Pazulu Source Engine : 15 profils de sources, un inspecteur DOM commun et des adaptations declaratives par site.
- Lecture dans le HUD existant depuis une page autorisee (analyse manuelle du DOM dans la WebView integree, sans navigateur externe).
- Option d’enregistrement en CBZ via le moteur hors ligne existant.
- Packs JSON de mise a jour avec validation des identifiants, versions, domaines et selecteurs ; validation atomique, copie .bak et confirmation des changements de domaine.
- MangaDex garde son API ; WEBTOON FR/EN et Aethon restent en mode site officiel, sans extraction.
- Les extracteurs generiques sont experimentaux : aucun support garanti sur un site tiers sans test reel et verification des permissions.
- Aucun changement dans le theme, les animations, le lecteur, les composants communs ou la navigation visuelle de v0.4.2.
- Tests unitaires du catalogue, du moteur et des mises a jour declaratives ajoutes.
- Non compile dans l’environnement de l’assistant : compiler et tester sur Windows/Android avant validation.

# Journal des versions

## 0.4.2 — 5 novembre 2026

- Correctif du plantage rapporte en 0.4.1 : suppression de `webview_flutter_windows` (capture de la vue native dans une texture Flutter).
- Windows : `webview_win_floating` 3.0.3, vue WebView2 native HWND integree dans la zone de lecture de l'unique fenetre Pazulu ; pas de lancement Edge externe.
- Garde anti-crash persistante : si une fermeture brutale survient pendant la lecture integree, Pazulu evite de rouvrir automatiquement la vue au prochain essai ; nouveau test manuel possible.
- Profil WebView2 dans le dossier de donnees utilisateur, compatible avec installation dans un dossier non inscriptible.
- Tests du marqueur d'interruption Windows.
- **Design entierement conserve** : theme, six palettes, animations, shell, composants et lecteur maison strictement identiques.
- Validation Windows **non effectuee ici** : compilation et test reel chez l'utilisateur requis.


## 0.4.1 — 5 novembre 2026

- **Une seule fenetre de lecture** : les chapitres officiels et les sources se chargent dans une WebView integree a Pazulu Reader sur Windows (WebView2 en texture Flutter) et Android.
- Supprime le lancement Edge `--app=...` et le bouton qui ouvrait le chapitre dans un navigateur externe.
- Ajoute un ecran de consultation interne pour les 15 adresses et les liens d'œuvres sauvegardes.
- Controle de l'URL (HTTPS seulement), verifie le runtime WebView2 Windows, affiche les erreurs dans Pazulu Reader avec une option de nouvel essai et journalise les echecs.
- Empêche les fenetres contextuelles externes du moteur Windows ; les parcours exigeant une popup peuvent ne pas fonctionner.
- **DA intacte** : `lib/design/theme.dart`, `lib/ui/shell.dart`, `lib/ui/widgets/motion.dart`, les couleurs, les animations et la mise en page generale n'ont pas ete modifies.
- Le lecteur natif CBZ/MangaDex et le moteur de detection V0.4.0 restent inchanges.
- Tests de validation des URL ; controles statiques effectues, **compilation et tests Windows reels a faire sur PC**. Voir `docs/LECTURE_INTEGREE_0.4.1.md`.


## 0.4.0 — 5 novembre 2026

- **Direction artistique inchangée** : six thèmes, rail latéral, animations et design tokens conservés sans modification.
- Découvrir → **Voir mes 15 sources** : les adresses FR/EN fournies, filtrables par langue, accès direct au site sans extension Firefox.
- Découvrir → **Créer une fiche** : ajouter une œuvre qui n'existe pas dans MangaDex, sans lui attribuer de faux chapitres ou de fausse surveillance.
- Fiche d'œuvre → **Autres sources** : rattacher et retirer l'adresse HTTPS d'une œuvre sur un site du catalogue ; liens enregistrés dans la bibliothèque et les sauvegardes `.pazulu`.
- **Détection corrigée** : historique persistant par site + langue + chapitre canonique. Détecte la traduction française d'un ancien chapitre même si le dernier chapitre anglais est beaucoup plus avancé ; évite les doublons de groupes et ignore les chapitres datés dans le futur.
- MangaDex : dernières sorties demandées **par langue séparée**, pour éviter de perdre les sorties FR derrière une longue liste EN.
- Réglages → Nouveautés : vérification automatique désactivée / 15 / 30 / 60 / 120 minutes quand l'application est ouverte, avec ralentissement en cas d'erreurs ; toujours une vérification manuelle.
- Restauration `.pazulu` : fusion des historiques de détection et des liens de sites, sans effacer les chapitres déjà observés.
- Tests supplémentaires : détection tardive, migration ancienne bibliothèque, doublons, publication future, catalogue et validation des liens.

**Statut réel :** seul MangaDex dispose d'un connecteur actif permettant la lecture interne et le téléchargement CBZ. Les 14 autres sources sont accessibles comme liens ; pas d'extraction de leurs chapitres ni de surveillance automatique sur ces sites en v0.4.0. Pas de planning opérationnel encore. Ce code n'est pas compilé/testé dans l'environnement de l'assistant (SDK Flutter absent) ; valider sur le PC avec `Compiler.cmd`.


## 0.3.0 — 5 novembre 2026

- Hors ligne : bouton de téléchargement sur chaque chapitre MangaDex ; le chapitre est enregistré en .cbz et se lit sans connexion (mention « hors ligne » dans le lecteur). Sans réseau, la fiche affiche les chapitres téléchargés.
- Import de fichiers .cbz / .zip déjà présents sur l'appareil (Bibliothèque → icône d'import) : une œuvre par dossier, numéro de chapitre lu dans le nom du fichier.
- Réglages → Hors ligne : nombre, taille, ouverture du dossier.
- Diagnostic.cmd : récupère les plantages enregistrés par Windows et la fin du journal, pour corriger la lecture intégrée des chapitres officiels sur PC.
- Les chapitres des sites officiels ne sont pas téléchargeables (accès contrôlé par les plateformes).


## 0.2.2 — 5 novembre 2026

- Correction : l'ouverture d'un chapitre officiel fermait l'application sous Windows (vues web intégrées incompatibles avec Flutter 3.47 sous Windows). Sur PC, le chapitre officiel s'ouvre désormais dans une fenêtre de lecture dédiée (Edge en mode application, profil Pazulu) ; sur Android, il reste intégré (webview_flutter officiel).
- Correction : les filtres Tous / EN / FR / Non lus de la fiche ne s'étirent plus sur toute la largeur.
- Si la vue web ne peut pas démarrer, Pazulu affiche un message et un bouton « Ouvrir le site officiel » au lieu de se fermer ; l'erreur est notée dans pazulu.log.
- Corrections mineures signalées par l'analyse statique.


## 0.2.0 — 5 novembre 2026

- Nouvelle interface « Néon nuit » : rail latéral animé, grand bandeau « Reprendre » avec la couverture floutée en fond, étagère « En cours », colonne des dernières sorties, fiche d'œuvre refaite (langues disponibles, chapitres manquants, pastilles Lecteur 1 / Lecteur 2 sur chaque chapitre, filtres Tous / EN / FR / Non lus).
- Six thèmes de couleur : Nuit indigo, Océan, Braise, Jade, Sakura, Or (Réglages → Thème), contrastes vérifiés.
- Animations : fond lumineux qui dérive, apparition en cascade, survol des couvertures, entrée des onglets, barre de progression animée, chargements pulsés. Toutes coupées par « Réduire les animations ».
- Lecteur officiel intégré : les chapitres publiés sur le site de l'éditeur (ex. Webnovel) s'affichent dans Pazulu, avec « Marquer comme lu » et chapitre suivant/précédent.
- Correction : un seul filtre actif à la fois dans la Bibliothèque.
- Compilation Windows : installation automatique de NuGet (nécessaire au lecteur officiel).


## 0.1.0 — 4 novembre 2026

Première version (phases 0 et début de 1–2 du plan).

- Cœur métier : clés canoniques de chapitres, regroupement multisource, classement des lecteurs, détection des chapitres manquants par langue, reprise de lecture.
- Connecteur MangaDex : recherche, fiche, liste complète des chapitres EN/FR, dernières sorties, pages (avec repli « qualité réduite »), limitation à 4 requêtes/s.
- Lecteur : vertical, pages G→D et D→G, zoom, préchargement, sélecteur Lecteur 1/2/3, bascule automatique, raccourcis clavier, mode immersif Android.
- Bibliothèque : statuts, favoris, filtres, tri, colonnes.
- Nouveautés : vérification à l'ouverture et manuelle, dédoublonnage par (œuvre, chapitre, langue).
- Stockage JSON versionné (migrations), écriture atomique, copie de secours, 7 sauvegardes automatiques, export/import `.pazulu` avec SHA-256 et fusion.
- Scripts : compilation Windows + Android, installateur Inno Setup.

Décisions par rapport au document d'architecture :

- Stockage en JSON plutôt que SQLite/Drift pour cette première version : moins de dépendances natives à valider sur Windows. Le format est versionné ; la migration vers SQLite est prévue quand la bibliothèque grossira.
- Connecteur MangaDex écrit en Dart. L'hôte QuickJS (connecteurs JS à chaud) arrive en phase 2 ; le contrat `ContentSource` est déjà celui que les connecteurs JS respecteront.
- Pas de bibliothèque de gestion d'état externe (Riverpod) : `ChangeNotifier` intégré à Flutter, suffisant à cette taille.

Non vérifié : compilation et exécution (outils Flutter indisponibles dans l'environnement de développement de l'assistant).
