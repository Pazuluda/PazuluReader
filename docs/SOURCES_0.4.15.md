# Pazulu Reader 0.4.15 — Sources et detection

## Ce qui fonctionne

- Les 200 adresses du document du 5 novembre sont livrees dans `assets/suggested_sources.json`, chargees au demarrage et visibles directement dans **Sources de lecture**, sans 200 ajouts manuels.
- Le repertoire initial de 13 sites est conserve. Quatre sites deja presents sont fusionnes par domaine. Les deux anciens sites archives restent accessibles via les identifiants historiques des bibliotheques sauvegardees.
- Les recherches dans **Sources** filtrent instantanement par nom, adresse et langue. Les lignes sont construites a la demande pour maintenir l'interface fluide.
- Les sites du nouveau repertoire peuvent etre ouverts dans la fenetre Pazulu et controles individuellement (HTTP/sante). Un controle de site ne garantit pas qu'une oeuvre ni qu'un chapitre soit disponible.
- Les 13 sources initiales et les sources personnelles continuent leurs controles periodiques tant que l'application est ouverte ; on ne bombarde pas automatiquement les 200 domaines.
- La progression, la base locale et les sauvegardes ne sont pas transformees.

## Ce qui n'est PAS livre comme valide

- Le fichier de 200 domaines ne constitue pas 200 extensions ni 200 moteurs de recherche de chapitres. 104 catalogues etaient accessibles au controle du document initial, 10 partiels, 86 non confirmes. Ces etats sont anciens et ne garantissent pas la lecture.
- La recherche automatique d'oeuvres et le chargement des pages reposent encore sur MangaDex et Pepper&Carrot ; les autres sites n'offrent pas encore de connecteur recherche + catalogage + pages verifie de bout en bout. Certains sites interdisent la recuperation des pages ou ont des contenus payants.
- Les pages impossibles a acceder, protegees ou expirsees ne sont pas contournees. Un site ne doit pas etre marque « chapitres lisibles » sans test de bout en bout.

## Tests demandes sur Windows

1. Extraire l'archive dans un nouveau dossier et lancer `Compiler-Windows.cmd`.
2. Ouvrir `Sources de lecture`, chercher `blossom-scans` : la premiere adresse du repertoire doit apparaitre sans action Ajouter.
3. Chercher `asurascans` : un seul site doit apparaitre, pas deux doublons.
4. Filtrer `Annuaire ajoute` : 196 sites si aucune de ces adresses n'avait ete enregistree precedemment comme source personnelle.
5. Ouvrir le menu d'une source et lancer `Verifier maintenant` ; ne pas confondre « Site accessible » avec « Chapitre lisible ».
6. Rechercher `Solo Leveling` dans Decouvrir : la couverture native reste limitee par les connecteurs disponibles, elle ne s'etend pas automatiquement aux 200 adresses.

Si la compilation echoue, transmettre `dist/build-log.txt`. Le fichier de theming et le HUD de lecture restent inchanges.
