# Journal de tests — Pazulu Reader 2.0.0

## Ce qui a réellement été exécuté
| Vérification | Résultat |
|---|---|
| Analyse syntaxique Dart (tree-sitter, grammaire Dart 3) de **tous** les fichiers `lib/` et `test/` | 0 erreur. Étalonnage : 0 erreur aussi sur le code V0.5.4 d'origine. |
| Contrôle maison des imports manquants et des noms ambigus entre imports | 0 problème. |
| Relecture ligne à ligne des fichiers nouveaux/modifiés (typage, promotions, nullabilité) | Corrections appliquées (nettoyage des requêtes en vol, clé d'œuvre sans `?#`, imports inutiles). |

## Ce qui n'a PAS pu être exécuté
- `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build windows --release` : **non exécutés**. L'environnement de développement n'avait ni Flutter ni Dart, pub.dev et storage.googleapis.com y étaient bloqués, l'exécution d'un SDK Dart récupéré sur conda-forge a été refusée par la politique de sécurité, et l'accès au dossier `~/dev/flutter` de votre PC a été refusé.
- Aucun test en direct sur un site (aucun domaine source n'était joignable).

**Conséquence : cette version ne doit pas être qualifiée de stable avant que `Compiler-Windows.cmd` ait réussi sur votre PC.** Le script s'arrête et liste honnêtement chaque étape en échec dans `dist\build-log.txt`.

## Tests livrés (à lancer avec `flutter test`)
| Fichier | Couvre |
|---|---|
| `test/engine_v2_identity_test.dart` | Extra ≠ chapitre 1, bonus de volume, 115.1 ≠ 115.2 ≠ 115.10, libellés (« Kaiju No. 8 Chapter 100 »), équivalences d'édition, Dress-Up Darling / Slime FR-EN-JP, titres proches distincts. |
| `test/engine_v2_validation_test.dart` | Dimensions PNG/JPEG/GIF/WebP sans décodage, HTML déguisé, paywall, âge, cookies, CAPTCHA ; 14/14 = COMPLETE, 8/14 = PARTIAL, « subscription required » = RESTRICTED, pas de faux 1/1, spinner/logo/pixel, doublons, webtoon étroit, 403. |
| `test/engine_v2_html_test.dart` | **Test A** (ts_reader 14 pages dans l'ordre, total détecté, 8/14 jamais présenté comme réussi, 20 pages sur un autre chapitre), **B/C** (fixtures Manga UP! et K MANGA), **E** (lazy-load Madara, webtoon vertical, chapitre JavaScript, webnovel texte, liste de chapitres avec décimaux/extra/bonus, recherche, changement de domaine, 429 + Retry-After, source hors ligne, SSRF, déduplication). |
| `test/engine_v2_router_test.dart` | **Test D** (erreur / 6 pages / incomplet ⇒ Lecteur 2), **B** (115.2 jamais interrogé, lien éditeur jamais repli), **C** (âge, langue exclue, volume différent ⇒ confirmation), 429, JavaScript, connecteur absent, extra ≠ 1, circuit breaker, classement. |
| `test/extensions_v2_test.dart` | Manifeste, domaines dangereux, version moteur, manifestes intégrés valides, pack SHA-256, pack altéré, chemin hors archive, installation/mise à jour/retour arrière/désactivation/suppression, tout-ou-rien, registre corrompu. |
| Tests V0.5.4 existants | Conservés sans modification. |

Fixtures : `test/fixtures/*.html` (pages construites pour reproduire les structures observées ; ce ne sont pas des copies de sites).

## Validation réelle à faire sur Windows
1. `Compiler-Windows.cmd` → vérifier « Termine sans erreur ».
2. Lancer l'EXE, ouvrir un chapitre MangaDex : la barre « Lecteur 1/2/3 » montre la source, la langue et une coche verte une fois les pages validées.
3. Paramètres → Moteur Pazulu → Diagnostic → « Tester cette source » sur MangaDex et SushiScan.net : noter le statut obtenu (`FULL_READER` attendu si un chapitre se charge).
4. Solo Leveling sur SushiScan.net : vérifier « page 1/14 … 14/14 » sans site visible.
5. Activer un profil (ex. ManhuaUS), le tester ; s'il échoue, envoyer le journal exporté (sans cookies ni jetons).
