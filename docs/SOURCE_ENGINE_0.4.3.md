# Pazulu Source Engine — V0.4.3

## But et perimetre

Un seul moteur generique pour les pages de lecture de sites compatibles, avec un profil de selecteurs CSS par source. Les profils sont des donnees, pas du JavaScript arbitraire ni des extensions Chrome/Firefox. Le script commun s'execute dans le WebView2 deja integre (Windows) ou WebView Android. Aucune seconde fenetre n'est requise.

## Architecture

- `lib/core/source_extensions.dart` : profils declares, import JSON versionne, verrouillage des modes officiels/natifs, validation atomique, alias de domaines, copie de secours `.bak`.
- `lib/core/page_inspection.dart` : generation du script DOM unique et validation des URL d'images HTTPS; ne sonde pas les requetes reseau et ne contourne aucune protection.
- `lib/core/sources/session_capture.dart` : pont de session avec le lecteur existant.
- `lib/ui/widgets/official_web_view.dart` : prise en charge de l'execution du script et masquage du HWND lors d'une boite de dialogue/du lecteur.
- `lib/ui/source_browser_page.dart` : bouton `Lire dans Pazulu`, choix lecture ou CBZ.
- `lib/ui/sources_page.dart` : import de packs de profils JSON.

## Etat des 15 adresses

| Source | Profil V0.4.3 | Verification en conditions reelles |
|---|---|---|
| MangaDex | Natif API existante | Connexion existante, non re-testee ici |
| ManhuaFast | Analyse DOM generique | Non testee |
| ManhuaUS | Analyse DOM generique | Non testee |
| AsuraScans | Analyse DOM avec selecteurs prioritaires specifiques | Non testee |
| Aethon Webcomics | Site officiel seulement | Pas d’extraction |
| ManhwaClan | Analyse DOM generique | Non testee |
| Scan-Manga | Analyse DOM generique | Non testee |
| EN-ThunderScans | Analyse DOM generique | Non testee |
| ToonGod | Analyse DOM generique | Non testee |
| Swordhound | Analyse DOM generique | Non testee |
| SSS-Class Hunter | Analyse DOM generique | Non testee |
| ManhuaTop | Analyse DOM generique | Non testee |
| KingofShojo | Analyse DOM generique | Non testee |
| WEBTOON FR | Site officiel seulement | Pas d’extraction |
| WEBTOON EN | Site officiel seulement | Pas d’extraction |

**Important :** un profil d'analyse DOM n'est pas un connecteur valide de lecture automatique ou de suivi des sorties ; cette fonction necessitera des validations et des connecteurs par site.

## Utilisation

1. Double-cliquer `Compiler-Windows.cmd` dans le dossier extrait.
2. Lancer `dist\PazuluReader-0.4.3-windows\pazulu_reader.exe` une fois la compilation reussie.
3. `Decouvrir` > `Voir mes 15 sources`, puis ouvrir une source compatible.
4. Naviguer jusqu'a une page de chapitre **accessible et autorisee** dans le site integre.
5. Cliquer `Lire dans Pazulu` : si des images exploitables sont detectees, choisir `Lire` ou `CBZ et lire`.
6. Les images doivent pouvoir etre chargees par le lecteur ; un fournisseur qui exige un cookie/referer peut rendre le chargement impossible. Le mode site officiel reste disponible.

## Mise a jour d'un profil

Dans l'interface : `Sources de lecture` > `Importer une mise a jour des sources (.json)`.

Exemple `packs/EXEMPLE_PROFILE_NE_PAS_INSTALLER_SANS_ADAPTATION.json` ; le selecteur fictif DOIT etre remplace par le selecteur reel avant utilisation. Chaque profil contient : `id` existant, `version` croissante, `mode`, `selectors`, `minimumWidth`, `minimumHeight`, `hostAliases` et `homeOverride`. Une mise a jour peut etre partielle (un site). Si un site change de domaine, le pack peut specifier un alias et une URL de depart ; une confirmation est demandee. Ne jamais installer un pack de source inconnue : un faux domaine peut usurper un site.

En cas d'erreur JSON, le pack est refuse en entier. Les versions anterieures ne sont pas effacees. Une copie `.bak` est conservee localement.

## Restrictions et points a tester

- Un clic utilisateur est necessaire ; pas de collecte automatique d’images pour l’ensemble des sites.
- Pas de traitement de DRM, de pages premium, ni de contournement des mecanismes d'acces.
- Impossible d'assurer la compatibilite des sites sans tester chaque site et ses conditions.
- Le lecteur maison et les autres ecrans conservent leurs styles. Les fichiers de design n'ont pas ete modifies.
- Une capture hors ligne est conservee via CBZ ; une simple capture en memoire peut necessiter de reouvrir le site apres redemarrage.
- La surveillance de nouveautes multisources, les adaptateurs de recherche/chapitres et l'automatisation des mises a jour demeurent des chantiers futurs.
- Si le lecteur charge des images CDN avec un `Referer` specifique ou une session privee, la lecture et le CBZ peuvent echouer ; l'application ne doit pas contourner cette restriction.

## Validation requise

Sur Windows : lancer `Compiler-Windows.cmd`, verifier `flutter test`, la compilation et la sortie `dist\build-log.txt`. Tester chaque site, la navigation par chapitre, la lecture native, l'option CBZ, les popups et le retour au navigateur. Faire de meme sur Android une fois le SDK installe. Sans ces essais, pas de declaration « 15 connecteurs operationnels ».
