# Pazulu Reader 0.4.16 — Connecteurs web de découverte (expérimentaux)

## Problème vérifié dans la V0.4.15

La page Découvrir n'interrogeait que MangaDex et Pepper&Carrot. Les 200 URL
étaient disponibles uniquement dans l'annuaire. Aucune recherche sur les pages
de ces domaines n'était effectuée.

## Modifications réelles

- Dans **Découvrir → Sites web : N choisis**, sélectionner les domaines à
  interroger (au plus 12 pour éviter une charge excessive sur des sites tiers).
- Pour un terme de recherche, les sources natives sont interrogées, puis les
  sites sélectionnés **par lots de quatre**. Chaque requête est limitée en
  temps et le rapport distingue une fiche HTML reconnue d'une erreur HTTP.
- Le moteur générique reconnaît les cartes de recherche WordPress/Madara
  exposées publiquement. Il vérifie que le titre correspond aux termes
  recherchés et que la fiche appartient bien au site choisi. Il essaie le
  formulaire WP-Manga puis la recherche WordPress standard.
- Le résultat est rattaché à la bonne source et peut exposer son **index HTML
  public de chapitres** (sans garantie d'exhaustivité).
- Les chapitres de cet adaptateur sont explicitement des **liens externes**.
  Le moteur **ne télécharge aucune image**, ne contourne aucun blocage et ne
  présente pas une simple URL comme lecteur natif fonctionnel.
- Les adaptateurs sont enregistrés au démarrage, sans réseau, pour pouvoir
  relire après redémarrage une fiche sauvegardée issue de la recherche.

## Limites et statut réel

- Toutes les 200 adresses sont sélectionnables ; **leur compatibilité n'est pas
  validée individuellement**. Les SPA, JavaScript-only, Cloudflare, sites en
  maintenance, API privées et mises en page différentes peuvent échouer.
- Il reste **deux connecteurs de pages natifs**. Les connecteurs de lecture
  pour les autres sites doivent être développés avec les autorisations
  appropriées et testés individuellement.
- La détection des sorties et le cache CBZ existants ne sont pas modifiés.
- Il ne faut pas annoncer « 200 connecteurs fonctionnels » à partir de cette
  version. Les rapports de recherche détaillent les échecs.

## Test Windows

1. Décompresser dans un nouveau dossier ; lancer `Compiler-Windows.cmd`.
2. Dans **Découvrir**, ouvrir **Sites web : N choisis** et sélectionner une
   source WordPress/Madara ; chercher un titre connu.
3. Déplier **Rapport de recherche des sites web** ; vérifier si une fiche
   correspondante a été trouvée ou si l'accès est bloqué.
4. Ouvrir la fiche ; vérifier que les chapitres ne sont **pas** présentés
   comme images intégrées sans vrai connecteur de pages.
5. Pour un site JavaScript-only ou protégé, vérifier qu'aucun résultat
   artificiel n'est inventé et que l'erreur apparaît.
6. Confirmer le comportement inchangé de MangaDex, Pepper&Carrot, des
   sauvegardes et du lecteur local.

Les tests Flutter sont fournis mais **ne sont pas exécutables dans cet
  environnement** sans SDK Dart/Flutter. Validation Windows requise.
