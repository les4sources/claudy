# Claudy

## Finalité de l'application

Cette application est principalement une plateforme de gestion de séjours. Elle permet de créer et suivre des séjours (Stay) pour des clients, incluant divers éléments comme des hébergements, des chambres, des lits, des espaces, des expériences, des produits, ou encore des objets de location. L’objectif est de faciliter l’administration de réservations complexes composées de multiples éléments, tout en assurant une bonne traçabilité (dates, paiements, etc.).

## Fonctionnalités principales

### Gestion des séjours (Stay)

- Création de séjours avec ou sans client associé
- Ajout dynamique d’éléments (StayItem) à un séjour (lit, chambre, produit…)
- Attribution de dates précises aux éléments via StayItemDate

### Modèle polymorphe StayItem

- Lien entre un séjour et des entités polymorphiques (Room, Bed, RentalItem, etc.).
- Formulaires interactifs avec Hotwire
  - Utilisation de Turbo Frames et Turbo Streams pour ajouter des éléments au séjour sans recharger la page.
  - Ouverture de modales pour sélectionner des objets à associer au séjour.

### Gestion des clients (Customer)

- Création via formulaire imbriqué (accepts_nested_attributes_for)

### Affichage et organisation

- Tri personnalisé des éléments du séjour par type (ex. : Space, puis Lodging, Room, etc.)
- Affichage sous forme de tableau avec actions (supprimer, modifier…)

### Support de la planification

- Attribution de dates précises à chaque StayItem

### Paiements

- Les séjours peuvent avoir des paiements associés (Payment), fonctionnalité à développer ou étendre
- Paiements en ligne via Stripe

## Technologies et conventions utilisées

- Ruby on Rails (version 7+)
- Hotwire : Turbo Frames, Turbo Streams, StimulusJS pour les interactions dynamiques (ex. déclenchement de contrôleurs au changement de date)
- Vite + vite-rails pour la gestion des assets JS/CSS
- PostgreSQL comme base de données
- puma-dev en environnement local (ex. : http://vite.claudy.test)
- TailwindCSS pour le design
- ViewComponent (optionnel : à confirmer si utilisé)
- Decoration avec Draper : utilisation de @stay.stay_items.decorate
- CSP (Content Security Policy) : renforcée, nécessite ajout explicite des URLs ws:// et http:// pour Vite en développement.
- Polymorphic associations : StayItem utilise belongs_to :item, polymorphic: true