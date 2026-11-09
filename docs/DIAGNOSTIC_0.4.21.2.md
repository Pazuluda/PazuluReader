# Pazulu Reader V0.4.21.2 — Suwayomi : "No chapters found"

## Diagnostic prouve par le test utilisateur

Le script atteint Suwayomi sur 127.0.0.1:4567, retrouve Solo Leveling via Scan-Manga,
mais la mutation `fetchMangaAndChapters` renvoie l'erreur `No chapters found`.
Suwayomi Server la lance dans `Chapter.updateChapterListDatabase()` quand la liste de
chapitres fournie par la source est vide. Ce message n'est pas un plantage PowerShell.

## Correctifs

- `lib/core/sources/suwayomi.dart` traite l'erreur exacte
  `Extension : No chapters found` comme une liste vide de chapitres, sans
  inventer de pages et sans masquer les autres erreurs.
- `Tester-Connecteurs.ps1` rapporte le statut `source_no_chapters`,
  l'URL de la fiche si Suwayomi la fournit et le site source, au lieu
  de catégoriser tout comme une panne indifferenciee.
- Deux tests Dart du comportement d'erreur sont inclus.

## Ce que ce correctif NE resout PAS

- Il n'ajoute aucun chapitre à Scan-Manga ; l'extension amont doit fournir
  des liens natifs réellement accessibles. Un titre reserve aux editeurs
  ne devient pas lisible par un changement de parseur.
- Aucune compilation Windows reelle n'a ete executee ici (Flutter absent).
- Le test live sur le PC utilisateur n'a pas ete refait depuis cet environnement.

## Installation rapide (script seul)

Remplacer `pazulu_extensions/tools/Tester-Connecteurs.ps1` dans le dossier
V0.4.21.1 par celui contenu dans ce patch, puis relancer
`Tester-Connecteurs.cmd`. Aucun besoin de recompiler pour le diagnostic.

Pour la correction dans l'interface Flutter, compiler le projet V0.4.21.2.
