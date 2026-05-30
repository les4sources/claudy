# API privée pour agent IA — Claudy

## Context

L'app Claudy (Rails 7.0, gestion du Domaine d'Ahinvaux pour Les 4 Sources) n'est aujourd'hui accessible qu'en UI humaine (Devise) ou via le flow invité par token (`namespace :public`). Michael a besoin qu'un **agent IA** puisse **lire** les informations métier (réservations, disponibilités, catalogue, collectif, paiements) via une **API privée**, **bien documentée pour les agents** afin qu'ils découvrent et trouvent l'info facilement.

Décisions cadrées avec Michael :
- **Périmètre V1 : lecture seule** (aucune écriture).
- **Auth : jeton statique en header `Authorization: Bearer <token>`**.
- **Forme : API REST JSON + spec OpenAPI 3** (standard lisible par tous les agents).
- **Données exposées : tous les domaines** — réservations/disponibilités, logements/chambres/espaces, humains/collectif, paiements/compta.

Aucune API n'existe encore. `jbuilder` est déjà dans le `Gemfile` ([Gemfile:28](Gemfile:28)) ; aucune gem de doc d'API, rate-limit, jwt ou CORS n'est installée.

## Approche générale

Nouveau `namespace :api do namespace :v1`, isolé de l'auth Devise et du flow public. Controllers basés sur `ActionController::API` (pas de cookies/CSRF/layout). Sérialisation via **jbuilder** (déjà présent, convention Rails). Documentation via un **fichier OpenAPI 3 écrit à la main** (descriptions riches orientées agent) servi par l'API, complété par un **endpoint d'index/découverte** en JSON.

Server-to-server uniquement → pas de CORS. Read-only → pas de CSRF à gérer.

## Authentification

- `Api::V1::BaseController` avec `before_action :authenticate_agent!`.
- Lecture du header `Authorization: Bearer <token>`, comparaison **constant-time** via `ActiveSupport::SecurityUtils.secure_compare` contre le secret.
- Secret stocké dans `ENV["AGENT_API_TOKEN"]` pour coller à la convention dotenv existante (Stripe/Postmark sont déjà en ENV) ; ajouter l'entrée dans `.env.example`. (Alternative : `Rails.application.credentials.agent_api_token` — au choix, ENV recommandé pour la cohérence.)
- Échec → `401` JSON `{ "error": "unauthorized" }`. Supporter une liste de jetons séparés par virgule pour permettre la rotation.
- `rescue_from ActiveRecord::RecordNotFound` → `404` JSON ; `rescue_from` paramètres invalides → `422`.

## Endpoints (tous GET, lecture seule)

**Découverte & doc**
- `GET /api/v1` — index JSON pour agents : URL de base, mode d'auth, liste des ressources avec description d'une ligne, lien vers la spec, exemple de requête.
- `GET /api/v1/openapi.json` — sert la spec OpenAPI 3.

**Réservations & disponibilités** (cœur métier)
- `GET /api/v1/bookings` — filtres `from_date`, `to_date`, `status`, `lodging_id` ; paginé.
- `GET /api/v1/bookings/:id`
- `GET /api/v1/space_bookings` (+ `/:id`)
- `GET /api/v1/availability?from=&to=&lodging_id=` — calcule la dispo en **réutilisant** `Lodging#available_between?`/`available_on?` ([lodging.rb:28](app/models/lodging.rb:28)) et `Space#available_on?` ([space.rb:21](app/models/space.rb:21)). Retourne, par logement/espace et par date, disponible/occupé (+ `occupied_beds_count` pour les lits).

**Catalogue (réf. relativement statiques)**
- `GET /api/v1/lodgings` (+ `/:id`), `GET /api/v1/rooms` (+ `/:id`), `GET /api/v1/spaces` (+ `/:id`).

**Humains / collectif**
- `GET /api/v1/humans` (+ `/:id`), `GET /api/v1/cycles` (+ `/:id`), `GET /api/v1/cycle_actions`, `GET /api/v1/tasks`.

**Paiements / compta (sensible)**
- `GET /api/v1/payments` (+ `/:id`) — exposer statut/montant/méthode ; **ne pas** exposer les identifiants Stripe bruts (`stripe_payment_intent_id`, `stripe_checkout_session_id`).

**Règles transverses**
- Exclure systématiquement les enregistrements soft-deleted (`where(deleted_at: nil)` — le gem `soft_deletion` n'ajoute pas de default scope).
- Pagination via `will_paginate` (déjà présent, [Gemfile:77](Gemfile:77)) sur les listes : params `page`/`per_page`, méta `total`/`pages` dans la réponse.

## Sérialisation (jbuilder)

Vues sous `app/views/api/v1/<resource>/` avec un partiel `_<resource>.json.jbuilder` réutilisé par `index` et `show`. N'exposer que les champs utiles à l'agent (pas de colonnes internes superflues), inclure les associations clés en mode résumé (ex. un booking liste ses `reservations` chambre×date).

## Documentation OpenAPI

Fichier `config/openapi/v1.yaml` (committé) décrivant chaque endpoint, paramètre et schéma de réponse, avec des **`description:` rédigées pour un agent** (à quoi sert la ressource, quand l'utiliser, exemples de valeurs). Servi tel quel (converti en JSON) par `GET /api/v1/openapi.json`. Optionnel : page Redoc/Swagger via CDN pour relecture humaine — non requis pour les agents.

## Fichiers à créer / modifier

- `config/routes.rb` — ajouter le bloc `namespace :api { namespace :v1 { ... } }`.
- `app/controllers/api/v1/base_controller.rb` — `ActionController::API` + auth jeton + rescues JSON + helper pagination.
- `app/controllers/api/v1/{index,bookings,space_bookings,availability,lodgings,rooms,spaces,humans,cycles,cycle_actions,tasks,payments,openapi}_controller.rb`.
- `app/views/api/v1/**/*.json.jbuilder` — partiels + index/show par ressource.
- `config/openapi/v1.yaml` — spec OpenAPI 3 annotée pour agents.
- `.env.example` — ajouter `AGENT_API_TOKEN=`.
- (Optionnel V1) `rack-attack` pour throttle l'API — à décider plus tard.

## Tests

- Request specs RSpec sous `spec/requests/api/v1/` : 401 sans/ mauvais jeton, 200 + forme JSON avec jeton valide, filtres de dates, calcul de dispo, exclusion des soft-deleted, non-exposition des champs Stripe, pagination.
- Le repo n'a pas FactoryBot dans le `Gemfile` (specs actuelles = `models/` + `components/`). À l'implémentation : vérifier la stratégie de données des specs existantes et soit ajouter `factory_bot_rails` (groupe test), soit construire les enregistrements inline.

## Vérification

1. `bundle exec rspec spec/requests/api/v1` — tous verts.
2. Lancer l'app (`bin/dev`) puis, jeton défini dans `.env` :
   - `curl -H "Authorization: Bearer $AGENT_API_TOKEN" http://localhost:3000/api/v1` → index des ressources.
   - `curl http://localhost:3000/api/v1/bookings` (sans header) → `401`.
   - `curl -H "Authorization: Bearer $AGENT_API_TOKEN" "http://localhost:3000/api/v1/availability?from=2026-07-01&to=2026-07-07"` → dispo cohérente avec le calendrier UI.
   - `curl -H "Authorization: Bearer $AGENT_API_TOKEN" http://localhost:3000/api/v1/openapi.json | jq .` → spec valide.
3. Validation finale : pointer un agent réel sur `GET /api/v1` + la spec OpenAPI et confirmer qu'il découvre et requête les ressources sans aide.
