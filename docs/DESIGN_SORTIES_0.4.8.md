# Pazulu Reader 0.4.8 — Écran Sorties

## Intention

Refonte visuelle ciblée de « Sorties / Nouveautés », à partir du code 0.4.7.
Identité conservée : Nuit indigo et les cinq palettes alternatives existantes,
typographie Flutter du projet, rail de navigation, lecteur CBZ et transitions.

## Utilisation effective du skill UI UX Pro Max

Archive fournie : `ui-ux-pro-max-skill-2.15.0(7).zip`.
Fichier consulté : `.claude/skills/ui-ux-pro-max/SKILL.md`.
Recherches réellement exécutées dans `scripts/search.py` :

- `status alerts color contrast empty states --domain ux` : contraste 4.5:1,
  états vides utiles, ne jamais communiquer uniquement par la couleur.
- `compact status cards responsive layout --stack flutter` : LayoutBuilder,
  Row/Column, SizedBox et adaptation aux contraintes d'affichage.

Aucun « design system » de remplacement n'a été imposé : le système Pazulu
existant fait autorité (`lib/design/theme.dart`).

## Résultat dans l'interface

- Titre et sous-titre de suivi, cadence et dernière vérification explicites.
- Quatre tuiles de bilan : œuvres suivies, flux vraiment vérifiés,
  chapitres disponibles non lus, contrôles en échec. Les tuiles utilisent
  « — » avant tout contrôle ; les sources simplement enregistrées ne sont
  pas comptées comme des flux contrôlés.
- Une carte par œuvre surveillée, avec couverture, état du flux et action
  « Lier une source ». Pour chaque flux : langue, résultat, dernier chapitre,
  lien « Lire » quand une disponibilité utilisable est connue.
- Les erreurs restent visibles, sans se déguiser en « aucune nouveauté ».
- Etat vide compact et non anxiogène pour les nouvelles publications.
- Adaptation desktop/mobile via LayoutBuilder, couleurs `context.pal`,
  états exprimés aussi avec du texte et une icône.

## Ce qui n'a PAS changé

- Aucun changement de la logique de récupération des chapitres, des API,
  de l'état AppState, de la synchronisation, des données de bibliothèque.
- Le seul changement dans AppState est le numéro de version.
- Les 13 sources et leurs limites techniques restent celles de 0.4.7.
- Une seule fenêtre : le mode WebView2 de la version précédente reste inchangé.

## Tester sur Windows

1. Extraire l'archive dans un dossier distinct.
2. Double-cliquer sur `Compiler-Windows.cmd`.
3. Ouvrir `dist\PazuluReader-0.4.8-windows\pazulu_reader.exe`.
4. Tester `Sorties > Vérifier`, puis tester avec une œuvre qui dispose
   d'un chapitre non lu, et avec une source qui échoue.
5. Tester l'application en 1250x850 et en fenêtre étroite (ex. 450 px).
6. Tester les six thèmes et les passages rapides entre onglets.

Le SDK Flutter n'est pas disponible dans l'environnement de création :
aucune compilation ou capture native de l'app n'est revendiquée ici.
En cas d'échec, transmettre `dist\build-log.txt`.
