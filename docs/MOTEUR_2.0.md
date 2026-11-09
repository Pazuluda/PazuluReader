# Pazulu Source Engine 2.0 — audit de la V0.5.4 et architecture

## 1. Audit de la V0.5.4

### Réutilisé tel quel ou étendu
| Élément | Décision |
|---|---|
| `ContentSource`, `SourceRegistry`, `SourceException` (`core/source.dart`) | **Conservés.** Le moteur ajoute des contrats *optionnels* (`PageResolvingSource`, `AvailabilitySource`, `BrowserRenderedSource`) au lieu d'une interface concurrente. |
| `SourceChapter`, `PageRef`, `WorkInfo`, `LibraryEntry`, `Settings` | Conservés, champs ajoutés avec valeurs par défaut (aucune migration de `library.json` nécessaire, retour arrière possible). |
| `ReaderFailover.validatePages` / `next` | Conservés et toujours appelés ; le Smart Source Router s'ajoute par-dessus. |
| `SourceRouting.rank` (niveaux hors ligne / natif / externe) | Conservé ; le classement par fiabilité (`SourceRanker`) n'agit qu'à l'intérieur d'un même niveau et d'une même langue. |
| `ChapterPagination.totalFromHtml`, `visiblePagesScript`, `browserTurnToPageScript` | Conservés : ils alimentent le moteur (total annoncé, rendu WebView2). |
| `SourceHealth*` (sondes d'accueil) | Conservé pour le répertoire ; la santé **des connecteurs** (lectures réelles) est un nouveau magasin. |
| MangaDex, Pepper&Carrot, SushiScan | Conservés, branchés comme extensions « natives » désactivables. |

### Fragile — corrigé
| Problème | Correction |
|---|---|
| `ChapterKey.parse("Extra 1")` donnait `"1"` : un extra était fusionné avec le chapitre 1. | Extras/bonus/spéciaux ont leur propre clé (`extra-1`, `bonus-2`, `side-story-3`). |
| `ChapterKey.parse("Volume 12 - Bonus")` donnait `volume-12` (fusion avec le volume). | Clé `volume-12-bonus`. |
| `115.10` et `115.1` partageaient la même clé (conversion en `double`). | Décimales conservées telles qu'écrites ; seul `12.0` → `12`. |
| Un titre comme « Kaiju No. 8 Chapter 100 » pouvait être lu « 8 ». | `ChapterLabelParser` : marqueur explicite prioritaire, sinon dernier nombre. |
| SushiScan : `#readerarea` vide dans le HTML, 1 image visible sur 14. | Lecture de la liste officielle `ts_reader.run({...})` du HTML public : les 14 pages dans l'ordre, sans WebView ; sinon WebView2 invisible page par page (existant). |
| Une page d'erreur, de paywall ou de vérification d'âge pouvait passer pour une planche. | `AccessDetector` (texte HTML/WebView) + `ImageSniff` (octets réels : PNG/JPEG/WebP/GIF/AVIF, HTML déguisé, dimensions) + `PageValidationEngine`. |
| Lecture « réussie » sans vérifier qu'une image soit réellement une image. | Sonde des 1ʳᵉ, dernière et page médiane (48 Ko, `Range`) avant affichage. |
| MangaDex 429 : pas de prise en compte de `Retry-After`. | Délai respecté, aucune relance forcée. |
| Pas de protection SSRF ni de liste de domaines par connecteur dans le HTTP générique. | `EngineHttpClient` : HTTPS seul, domaines déclarés revérifiés à chaque redirection, DNS privé refusé. |
| Basculement vers « un autre lecteur » sans contrôle d'édition. | `CanonicalChapter.compare` : `exact` / `needsConfirmation` / `different`. |
| CBZ téléchargé *avant* d'afficher la 1ʳᵉ page. | Affichage immédiat, mise en cache CBZ en arrière-plan. |

### Redondant — conservé pour compatibilité
`SourceRecipe` (profils v1 de sélecteurs pour le navigateur intégré), `PublicCatalogSource`, `NativeEnginePage` : toujours fonctionnels, non supprimés (règle « ne pas désactiver les fonctions existantes »). Les nouvelles sources passent par les extensions v2.

### À remplacer plus tard (documenté, non fait)
- **Persistance SQLite (`drift`)** : non introduite. Le stockage JSON atomique avec `.bak` est conservé ; une migration non testée sur Windows risquerait les bibliothèques et progressions. Plan : schéma `drift` (works, chapters, progress, source_links, extensions, connector_health), migration lecture-seule du JSON, double écriture une version, puis bascule.
- **`dio`, `flutter_riverpod`** : non nécessaires ; `package:http` + `ChangeNotifier` existants suffisent pour le moteur. Éviter une réécriture de l'état global.

## 2. WebView2 : `webview_win_floating` vs `webview_flutter_windows`

Non migré. Raisons : (1) impossible de vérifier depuis l'environnement de développement les versions publiées, leur contrainte Flutter/Dart et leur compatibilité avec le SDK de `~/dev/flutter` ; (2) l'existant fournit déjà ce dont le moteur a besoin (`EmbeddedBrowserBridge.run`, `setVisible(false)` avant `loadRequest`, garde anti-crash). Le moteur ne dépend que de `EmbeddedBrowserBridge` : une migration vers un contrôleur headless (rendu Texture) ne toucherait que `official_web_view.dart`. À faire sur Windows, avec un test d'intégration, avant toute bascule.

Le moteur n'utilise WebView2 **que** si la source le déclare (`transport: "browser"` ou SushiScan) **et** si le HTML statique est insuffisant. Avant toute extraction, `accessProbeScript` lit le texte rendu : paywall, connexion, âge, CAPTCHA ⇒ restriction signalée, aucun clic ni réponse automatique.

## 3. Architecture

```text
lib/
  engine/                       Pazulu Source Engine 2.0 (aucun widget)
    engine_version.dart         version du contrat + SemVer
    availability.dart           AccessKind, ChapterAvailability, ChapterPages, PageCompleteness
    source_contract.dart        PageFetch, PageResolvingSource, BrowserRenderedSource
    identity/canonical_chapter.dart   CanonicalChapter, Equivalence, ChapterLabelParser
    http/engine_http.dart       client sûr (SSRF, 429, déduplication, LRU, débit par hôte)
    http/html_extract.dart      src/srcset/data-*/picture/noscript, ts_reader, Madara
    validation/                 AccessDetector, ImageSniff, PageValidationEngine
    routing/                    CircuitBreaker, ChapterResolver, SmartSourceRouter, SourceRanker
    discovery/discovery_engine.dart   normalisation, regroupement prudent, recherche bornée
    diagnostics/                journal expurgé, santé des connecteurs, tests de source, statuts
    cache/lru_cache.dart
    pazulu_engine.dart          façade
  extensions/
    manifest.dart               manifeste v2 validé
    pack.dart                   .pazulusource / .pazulupack (SHA-256)
    registry.dart               installation atomique, retour arrière, activation
    runtime/declarative_source.dart   connecteur niveau 1 (HTML / HTML+WebView2)
  ui/engine/                    Extensions, Diagnostic des sources
  ui/widgets/reader_switcher.dart     Lecteur 1 / 2 / 3
assets/extensions/              manifestes intégrés
```

Séparation stricte : **métadonnées** (`search`, `getWork`, `listChapters`) ≠ **disponibilité** (`AccessKind`) ≠ **pages** (`PageFetch`) ≠ **pages validées** (`ChapterPages`).

### Flux de lecture
```text
ReaderPage._loadPages
  └─ AppState.routeChapter → SmartSourceRouter.route
       pour chaque lecteur (ordre : hors ligne > natif, langue, préférence, fiabilité)
         ├─ identité ≠ demandée ⇒ ignoré (115.2 pour 115.1, roman pour manga)
         ├─ identité incertaine ⇒ pastille « édition à confirmer »
         ├─ lien éditeur / langue exclue / domaine en pause ⇒ ignoré
         └─ ChapterResolver.resolve
              ├─ PageFetch (API / HTML / ts_reader) — total annoncé par le SITE
              ├─ besoin de JavaScript ⇒ WebView2 invisible (lecteur)
              └─ PageValidationEngine (structure + sondes d'images)
                   COMPLETE / UNCONFIRMED ⇒ affichage ; PARTIAL / RESTRICTED / INVALID ⇒ lecteur suivant
```

### Circuit breaker
3 échecs consécutifs ⇒ domaine en pause 60 s, doublée à chaque récidive (max 15 min), puis un essai unique. HTTP 429 ⇒ pause exactement égale au `Retry-After` (plafonnée à 1 h).

## 4. Inspiration Paperback (concepts uniquement)
Séparation source / contrat / mises à jour indépendantes. Rien n'est copié ; Pazulu n'exécute aucun code d'extension : les extensions sont des données validées, les connecteurs complexes sont compilés avec l'application. Un futur bac à sable (isolat Dart sans `dart:io`, ou QuickJS sans accès réseau direct) est envisageable mais n'est pas livré.
