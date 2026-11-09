# Etat des sources dans Pazulu Reader 0.4.17

## Ne pas confondre ces quatre notions

1. **Adresse en repertoire** : 13 sources historiques + 196 adresses
   nouvelles issues de la liste de 200 (4 adresses etaient deja presentes).
   Cela ne dit RIEN du fonctionnement des recherches ou de la lecture.
2. **Connecteur installe** : un adaptateur Dart natif, ou une extension FR/EN
   effectivement signalee par Suwayomi sur 127.0.0.1:4567.
3. **Oeuvre trouvee** : titre / resume confirmes dans une source qui a repondu.
4. **Chapitre lisible** : ses pages sont obtenues au clic Lire et correctement
   chargees dans le HUD; un lien externe ou un HTTP 200 de page HTML ne suffit pas.

## Validation actuelle

- Connecteurs Dart natifs presents : MangaDex et Pepper&Carrot.
- Passerelle Suwayomi ajoutee en 0.4.17 : **non testee sur un serveur reel**.
- Nombre reel d'extensions installees : **inconnu tant qu'un serveur Suwayomi
  local n'a pas repondu**. Affiche dans Decouvrir apres connexion.
- L'ensemble des 209 adresses : **non valide comme 209 connecteurs**.
- Certains domaines peuvent etre fermes, non accessibles, payants, sans
  extension maintenue ou restreindre l'integration dans un lecteur tiers.

## Pour une preuve par source

Le prochain audit doit enregistrer pour chaque source : nom, domaine,
connecteur installe, resultat de recherche, liste de chapitres, disponibilite
des pages, date du dernier controle, motif d'echec. Ne jamais annoncer un
site comme fonctionnel sur la base de sa seule page d'accueil.
