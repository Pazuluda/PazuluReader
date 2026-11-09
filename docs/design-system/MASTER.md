# Pazulu — système de design (2.2)

Source de vérité des choix visuels. Les jetons vivent dans `lib/design/theme.dart`.

## Comment il a été établi

Le skill **UI UX Pro Max 2.15.0** (fourni dans le zip) a réellement été exécuté
(`scripts/search.py … --design-system`, plus des recherches `--domain ux`).
Ses recommandations ont été appliquées **dans la limite du cahier des charges** :

| Recommandation du skill | Décision Pazulu |
|---|---|
| Styles « Minimalism & Swiss » (lecture) ou « Vibrant & Block-based » (divertissement) | Base Swiss : surfaces pleines, peu d'effets, hiérarchie typographique. Couleur vive réservée aux actions et états. |
| Palette rose/bleu (#E11D48 / #2563EB) | **Refusée** : l'identité Indigo/violet est imposée. |
| Polices Righteous / Poppins | Non intégrées (pas de téléchargement de polices) ; police système, graisses 600–800 pour la hiérarchie. |
| Survol 150–300 ms, `prefers-reduced-motion` | `PazuluMotion` : 120 / 180 / 320 ms ; tout passe à 0 si le système réduit les animations. |
| Contraste texte ≥ 4.5:1, focus visible, cibles ≥ 44 px | Appliqué : texte #ECEDF5 et atténué #A3A6BF sur #0A0A12 ; boutons ≥ 44×44. |
| Pas d'emoji comme icône | Icônes Material arrondies uniquement. |

## Jetons

| Jeton | Valeur | Usage |
|---|---|---|
| background | #0A0A12 | fond d'application |
| surface | #14141F | rail, panneaux du lecteur |
| card | mélange fond/surface | cartes, lignes |
| surfaceHigh | #1E1E2E | survol, pistes |
| selected | surface + 22 % primary | élément actif |
| primary | #4F46E5 | bouton principal (texte blanc) |
| bright | #A5B4FC | liens, icônes actives, progression |
| accent | #7C3AED | dégradé, « nouvelle saison » |
| success / warning / danger | #4ADE80 / #FBBF24 / #F87171 | sortie confirmée, retard ou pause, hiatus |
| Rayons | 8 / 14 / 20 / pilule | petit, carte, panneau |

## Règles

- **Un seul bouton plein par écran** : l'action principale (Reprendre · Ch. N, Regarder sur …).
- Les actions secondaires vont dans un menu (« Sources ») ou en bouton contour.
- Lignes de chapitre : colonne de numéro fixe en chiffres tabulaires, barre d'accent pour le chapitre en cours, aucun titre redondant (« Chapter 115 »).
- Planning : chaque ligne commence par l'**heure** (exacte pour les animés, « vers HH:MM » pour un rythme régulier), bordure gauche colorée selon l'état.
- Lecteur : chrome en panneaux flottants qui glissent ; une fine ligne de progression reste visible quand l'interface est masquée ; fond noir, graphite ou sépia sombre.
- Aucune image n'est chargée pendant une recherche, sauf les couvertures déjà fournies par le catalogue.
