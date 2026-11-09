# Pazulu Reader 0.4.9 — correctif de compilation (+16)

## Erreur corrigée

`lib/ui/work_page.dart:523` : `isExternal` sur `SourceChapter?` ;
`lib/ui/work_page.dart:525` : `externalUrl` sur `SourceChapter?`.

La méthode `_ChapterRow.onOpen` accepte une variante nullable : un clic sur
la ligne transmet `null`, tandis qu'un clic sur un lecteur transmet sa
variante. On choisit maintenant une variante préférée ou, à défaut, on
propose la reprise dans le lecteur natif. Aucun accès direct à `v` tant
qu'il est nullable.

## Validation sur Windows

1. Extraire l'archive dans **un nouveau dossier** (ne pas mélanger avec la
   précédente V0.4.9).
2. Double-cliquer sur `Compiler-Windows.cmd`.
3. Le script exécute `flutter analyze`, `flutter test`, puis
   `flutter build windows --release`.
4. En cas d'échec, transmettre le nouveau `dist\build-log.txt`.
5. Après compilation réussie, lancer l'EXE depuis
   `dist\PazuluReader-0.4.9-windows\pazulu_reader.exe`.

Les avertissements du journal précédent sur les imports inutilisés ou les
accolades sont non bloquants. L'absence de SDK Android est également sans
conséquence pour `Compiler-Windows.cmd`.

Ce correctif n'est pas une preuve de compilation : Dart / Flutter ne sont
pas installés dans l'environnement où l'archive a été préparée.
