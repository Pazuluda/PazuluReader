# 0.4.18 - Verification de la couverture reelle

La liste de 209 sites du gestionnaire n'est pas un moteur a 209 lecteurs.

1. Installer Suwayomi Server depuis le depot officiel (pas une copie non fiable).
2. Demarrer le serveur sur 127.0.0.1:4567. Ne pas exposer son API sur internet.
3. Installer volontairement les extensions de lecture FR/EN desirees, en examinant leur provenance.
4. Lancer `Diagnostiquer-Sources.cmd` dans le dossier source Pazulu Reader.
5. Lire `dist/diagnostic-sources.txt`. Il indique si le serveur repond, quels
   connecteurs FR/EN sont exposes et quelles extensions repondent a une recherche
   de metadonnees Solo Leveling. Rien n'est telecharge pendant ce controle.
6. Dans Pazulu, actualiser les extensions depuis Decouvrir, puis revenir a la
   fiche de l'oeuvre et choisir « Chercher une source ».

En V0.4.18, la liste des extensions est actualisee au demarrage. Si elle change,
les caches temporaires de listes de chapitres sont invalides sans toucher aux
fichiers CBZ ni a l'historique de progression.

Limites : la recherche d'une oeuvre ne garantit pas sa disponibilite en lecture.
Une source peut ne posseder qu'une traduction partielle, proposer des contenus
payants ou refuser l'acces depuis un lecteur tiers. Un site peut rester dans
le repertoire sans disposer d'extension compatible. Pas de contournement des
DRM ni de protections techniques.

Pour une recherche diagnostic sur plus de sources installees :

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\diagnose_suwayomi.ps1 -Title "Solo Leveling" -MaxSources 50
```

Ne pas lancer des tests a haute frequence sur toutes les extensions.

ATTENTION : le code n'a pas ete compile ici sur Windows avec Flutter ;
utiliser Compiler-Windows.cmd pour verifier le build sur votre poste.
