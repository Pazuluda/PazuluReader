# Extensions Pazulu 2.0

Une extension décrit **où** et **comment** lire une source. Elle ne contient aucun code : Pazulu valide le JSON, puis le moteur fait toutes les requêtes lui-même.

## Deux niveaux
- **Niveau 1 — déclaratif** (`transport: "html"` ou `"browser"`) : sélecteurs CSS + familles intégrées. Modifiable sans recompiler.
- **Niveau 2 — natif** (`transport: "native"`) : adaptateur Dart compilé (`mangadex`, `peppercarrot`, `sushiscan_net`). Le manifeste sert alors à l'activer/désactiver et à documenter limites et tests.

## Formats
- `.pazulusource` : un manifeste JSON.
- `.pazulupack` : ZIP contenant `pack.json` et les manifestes :
```json
{ "format": "pazulu-pack", "schemaVersion": 1, "name": "Mes sources FR",
  "publisher": "Moi", "sources": [ { "path": "sources/pazulu.monsite.json",
  "sha256": "<empreinte du fichier>" } ] }
```
Le bouton « Exporter » d'une extension produit un `.pazulupack` valide.

## Manifeste (schemaVersion 2)
```json
{
  "schemaVersion": 2,
  "id": "pazulu.monsite",
  "name": "Mon Site",
  "version": "1.0.0",
  "languages": ["fr"],
  "contentTypes": ["manga", "manhwa"],
  "hosts": ["monsite.example"],
  "imageHosts": ["cdn.monsite.example"],
  "homeUrl": "https://monsite.example/",
  "capabilities": { "search": true, "chapters": true, "pages": true, "latest": true },
  "transport": "html",
  "paginationMode": "auto",
  "readingDirection": "auto",
  "imageMode": "referer",
  "rateLimit": { "requestsPerMinute": 20, "maxConcurrent": 1 },
  "minimumEngineVersion": "2.0.0",
  "validation": "IMPLEMENTED_UNTESTED",
  "enabledByDefault": false,
  "html": {
    "family": "madara",
    "restrictedTexts": ["chapitre réservé aux membres"]
  },
  "tests": [ { "kind": "search", "query": "Solo Leveling" } ],
  "notes": "Texte libre affiché dans Pazulu."
}
```

| Champ | Règle |
|---|---|
| `id` | `[a-z0-9]` séparés par `.` `_` `-`, ex. `pazulu.monsite`. Unique. |
| `version` | SemVer. Une mise à jour doit augmenter la version ; même version + contenu différent = refus. |
| `hosts` | 1 à 6 domaines publics. Refusés : IP, `localhost`, `.local`, `.internal`. Toute redirection hors de ces domaines est refusée (« la source a peut-être changé de domaine »). |
| `transport` | `html`, `browser` (HTML + WebView2 invisible si nécessaire), `native`. |
| `paginationMode` | `auto`, `vertical`, `horizontal`, `paged`. |
| `readingDirection` | `auto`, `ltr`, `rtl`, `vertical` (modifiable par l'utilisateur, mémorisé par œuvre). |
| `imageMode` | `referer` (Referer = URL du chapitre) ou `direct`. |
| `rateLimit` | 1–300 requêtes/min, 1–4 simultanées. |
| `validation` | `VERIFIED_LIVE`, `VERIFIED_FIXTURE_ONLY`, `IMPLEMENTED_UNTESTED`, `METADATA_ONLY`, `UNSUPPORTED`. Affiché tel quel. |

### Règles HTML
Familles : `madara`, `mangathemesia`, `custom`. Toute clé surcharge la famille :
`searchUrl` (`/?s={query}` ou URL complète sur un domaine déclaré), `searchItem`, `searchLink`, `searchTitle`, `searchCover`, `workTitle`, `workDescription`, `workCover`, `chapterItem`, `chapterLink`, `chapterTitle`, `chapterVolume`, `pageImages` (liste), `useTsReader`, `useMadaraPreloaded`, `pageCounter`, `restrictedTexts`, `seriesPathPrefix`, `chapterPathPattern` (expression régulière sur le chemin).

Les images sont lues dans `src`, `srcset` (plus grande résolution), `data-src`, `data-lazy-src`, `data-original`, `data-cfsrc`, `picture/source`, `noscript`. Logos, GIF de chargement, SVG, bannières, publicités sont écartés, puis le `PageValidationEngine` vérifie de vraies images.

## Sécurité
- Manifeste validé champ par champ ; sélecteurs sans `<`, `javascript:` ni contenu binaire.
- HTTPS uniquement, pas de port explicite, pas d'identifiants dans l'URL, DNS privé refusé (SSRF).
- Aucune extension n'accède au disque, aux bibliothèques, aux profils ou aux progressions : elle ne reçoit que des URL et du HTML.
- Installation atomique (manifestes écrits puis registre remplacé via `.tmp` + `.bak`), version précédente conservée → « Revenir à la version précédente ».
- Intégrité : SHA-256 de chaque fichier d'un pack. **Origine** : la signature cryptographique n'est pas encore vérifiée (pas de bibliothèque Ed25519 dans les dépendances actuelles) ; les packs utilisateur sont affichés « non signés » et demandent une confirmation. Les extensions intégrées sont livrées dans l'exécutable.
- Désactivation individuelle ; une extension intégrée se réinitialise mais ne se supprime pas.

## Ajouter une source pas à pas
1. Ouvrez un chapitre du site dans un navigateur, repérez le conteneur des pages.
2. Partez de la famille la plus proche (`madara` pour `.reading-content`, `mangathemesia` pour `#readerarea` + `ts_reader.run`).
3. Installez le `.pazulusource`, activez-le, cliquez « Tester cette source » (Paramètres → Moteur Pazulu → Diagnostic).
4. `FULL_READER` n'apparaît qu'après un chapitre réellement chargé et validé.
