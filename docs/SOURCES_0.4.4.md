# Pazulu Reader V0.4.4 — Ajout facile et sante des sources

## Nouveautes

- 13 sources actives conservees depuis V0.4.3.
- ManhuaFast et ManhwaClan sont sorties du catalogue actif. Leurs identifiants historiques sont conserves pour les anciens liens, sauvegardes et profils (aucune suppression des lectures).
- Ajouter une source personnalisee depuis **Decouvrir > Sources > Ajouter une source**. Une URL HTTPS publique suffit ; le nom est facultatif, les langues FR/EN sont configurables. Pas de navigateur ou extension externe et pas de recompilation.
- Les nouvelles sources reutilisent le moteur d'inspection commun de V0.4.3, a declencher volontairement sur une page de chapitre autorisee. Elles ne deviennent pas des connecteurs de recherche et de surveillance de chapitres automatiquement.
- Les sources personnelles peuvent etre desactivees et reactivees sans supprimer les liens de la bibliotheque.
- Controle automatique de disponibilite : 15 secondes environ apres le lancement, puis sur les sources dont le dernier controle remonte a 6 heures ou plus, tant que l'application est au premier plan. Bouton "Verifier les sources" et controles individuels disponibles.

## Les 13 sources conservees

ManhuaUS, AsuraScans, Aethon Webcomics, Scan-Manga, EN-ThunderScans, ToonGod, Swordhound, SSS-Class Hunter, ManhuaTop, MangaDex, KingofShojo, WEBTOON FR et WEBTOON EN.

Le catalogue est une liste de sites, pas la promesse que tous leurs chapitres peuvent etre extrais. Les sources de lecture officielle restent dans leur lecteur officiel lorsque l'integration n'est pas permise.

## Comment utiliser

1. Extraire l'archive et double-cliquer `Compiler-Windows.cmd`.
2. Une fois la compilation terminee, lancer `dist\PazuluReader-0.4.4-windows\pazulu_reader.exe`.
3. Ouvrir **Decouvrir > Gerer mes sources**.
4. Cliquer **Ajouter une source**, coller `https://nouveau-site.fr/`, choisir FR ou EN et valider.
5. La source apparait dans la liste. Un controle initial se lance si aucune verification n'est en cours.
6. Appuyer sur les trois points a droite de la source pour consulter les details, demander un nouveau controle, ou desactiver/reactiver une source personnelle.
7. Ouvrir le site en un clic. Naviguer jusqu'a un chapitre et, si l'usage est autorise et que ses pages sont compatibles, tester **Lire dans Pazulu**. Sinon la lecture du site officiel demeure disponible.

## Signification des diagnostics

- **Site accessible** : l'URL HTTPS renvoie une reponse HTML apparemment normale. Ne prouve ni la disponibilite des chapitres ni la compatibilite des extensions.
- **Acces limite / redirection** : 401, 403, 429, page de verification, ou redirection vers un autre domaine. Ne prouve pas que le site est ferme.
- **Incident temporaire possible** : erreur de DNS, TLS, timeout, 404, 500, 525, etc. On conserve la source.
- **Indisponibilite persistante** : au moins 3 echecs pendant 24 heures ou plus. C'est un soupcon, jamais une declaration de fermeture definitive ; la source n'est pas supprimee ni remplacee automatiquement.
- **Non verifie** : aucun controle local encore disponible.

Aucun scan agressif, contournement de protections ou telechargement du contenu n'est effectue par le controle de sante. La detection repose sur des requetes HTTPS legeres et limitees a l'URL d'accueil ; une page peut etre blanche dans WebView alors que le serveur repond normalement. Si un site change de domaine, l'utilisateur doit verifier la nouvelle adresse avant de l'ajouter.

## Stockage et securite

- Sources personnelles : `user-sources.json` dans le dossier de donnees de l'application ; un `.bak` est conserve lors d'une mise a jour. Les URLs de reseau local, `http://`, ports et identifiants dans l'URL sont refuses.
- Diagnostics : `source-health.json` (horodatage, statut, erreurs et compteurs). Ni cookie ni compte ne sont sauvegardes dans ce fichier.
- Bibliotheque / progression : `library.json` est inchange. Les anciennes lectures et sauvegardes ne sont pas supprimees.
- Les `.pazulu` existants continuent de sauvegarder la bibliotheque et les liens associes. **Pour migrer egalement la liste de sites personnels vers un autre ordinateur, copier `user-sources.json`** depuis le dossier de donnees applicatif. La fusion automatique de ce fichier dans l'export `.pazulu` est a realiser dans une version ulterieure.
- Aucun script executable distant n'est installe en ajoutant une source. Les sites personnalises utilisent seulement les selecteurs integres au moteur commun.

## Tests / limites

Les fichiers sources, tests unitaires et scripts de compilation sont livres. Dans l'environnement de preparation, Flutter et Dart ne sont pas installes : les tests `flutter test`, la compilation Windows et Android, et la compatibilite de chaque nouveau site doivent etre verifies sur le PC utilisateur. En cas d'erreur, envoyer `dist\build-log.txt`.

La detection automatique des **nouvelles publications de chapitres** sur les 13 sources n'est PAS terminee : ce developpement est distinct de la surveillance de leur disponibilite. MangaDex reste le connecteur de chapitres natif existant.
