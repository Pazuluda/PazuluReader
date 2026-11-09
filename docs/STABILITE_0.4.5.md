# Validation de la V0.4.5 (Windows)

1. Sauvegarder votre bibliotheque depuis les Reglages / export `.pazulu`.
2. Extraire dans un nouveau dossier, double-cliquer `Compiler-Windows.cmd`.
3. Lancer `dist\PazuluReader-0.4.5-windows\pazulu_reader.exe`.
4. Cliquer rapidement 40 a 60 fois entre les onglets principaux, faire defiler
   des listes et retourner sur les onglets deja visites.
5. Verifier la conservation des filtres, recherches et de la position de defilement.
6. Dans Sources, modifier une source personnelle (nom, URL ou langues).
   Si le domaine change, verifier la confirmation et les anciens liens.

Si l'application ferme encore : lancer `Diagnostic.cmd`, puis transmettre
`dist\diagnostic.txt` et `dist\build-log.txt` si la compilation a echoue.
Le journal Windows Application (evenements 1000,1001,1026) est indispensable
pour differencier une exception Flutter d'un crash natif WebView2/GPU/DLL.

Notes : Le code source n'a pas ete compile par l'assistant. La stabilite
sur Windows reste a confirmer. L'apparence, les six palettes, les animations
visibles et le lecteur ne sont pas modifies.
