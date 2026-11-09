<p align="center"><img src="assets/icon/app_icon.png" width="128" alt="Pazulu Reader"></p>

# Pazulu Reader

Lecteur de mangas, manhwas et webtoons **multisource** pour Windows, avec suivi des animés.

- **Lecture** : plus de 200 sources, même chapitre retrouvé d'un site à l'autre (FR/EN), lecteur page ou défilement, téléchargement CBZ.
- **Bibliothèque** : favoris, progression, nouveaux chapitres détectés, planning des sorties heure par heure.
- **Animés** : fiches et planning AniList, heure de sortie en France, Crunchyroll dans l'application (bon épisode, bonne saison), soirées à plusieurs avec [Roll With Your Friends](https://github.com/Pazuluda/roll_with_your_friends).
- **Mises à jour** : l'application vérifie les releases de ce dépôt et s'installe toute seule (bouton en haut à droite). Bibliothèque, progression et réglages sont conservés.

## Installer

Dans [Releases](https://github.com/Pazuluda/PazuluReader/releases/latest), télécharger :

- `PazuluReader-X.Y.Z-setup.exe` : installateur (aucun droit administrateur, installé dans `%LOCALAPPDATA%\Programs\Pazulu Reader`) ;
- ou `PazuluReader-X.Y.Z-windows.zip` : version portable, à décompresser.

Windows 10/11 64 bits. Le lecteur intégré utilise WebView2 (déjà présent sur Windows 11).

## Publier une version

1. Mettre le même numéro dans `lib/core/app_state.dart` (`appVersion`) et `pubspec.yaml`.
2. Fusionner dans `main`. C'est tout : le workflow `Release Windows` voit que cette version n'a pas
   encore de release, compile l'`.exe` et le `.zip`, crée le tag `vX.Y.Z` et publie la release (≈10 min).
   Les applications installées proposent la mise à jour à leur prochain lancement.

## Compiler soi-même

`Compiler-Windows.cmd` (Flutter 3.47, Visual Studio 2022 « Développement Desktop C++ »). Historique : `docs/CHANGELOG.md`, `docs/HISTORIQUE_README.md`.
