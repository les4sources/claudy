# Agenda — Vue "Organisation" (Gatherings)

**Date** : 2026-04-23
**Statut** : Design validé, en attente de plan d'implémentation
**Périmètre** : Chantier 1 — vue calendrier des moments collectifs

## Context

Les 4 Sources est un collectif de 8 sourciers en gouvernance partagée. Le PUD du 2026-04-02 a décidé (ou envisagé) la création d'un rôle "Gardien des plannings et des ODJ". Ce gardien doit pouvoir tenir à jour les dates et horaires des moments collectifs (PUD, chantiers, conseil des sourciers, mise au vert, rencontres archis…) et "aller à la pêche aux dates" de manière fluide.

Aujourd'hui, Claudy expose un calendrier mensuel (`pages#calendar`, route racine) centré sur les réservations d'hébergements et d'espaces (pour le pôle accueil). Rien dans l'interface ne permet de voir ou gérer les moments internes du collectif.

Ce chantier 1 introduit une vue **Organisation** sur ce même calendrier, accessible via un switch, dédiée aux moments collectifs. La préparation (ODJ, docs), les rappels, les décisions et les présences sont reportés à un chantier 2 dans la section `/organisation` existante.

## Objectifs

- Permettre au gardien de visualiser les moments collectifs d'un mois donné en un coup d'œil.
- Créer un moment en **2 clics** depuis le calendrier (clic sur le jour → clic sur la catégorie).
- Conserver la vue Réservations actuelle intacte ; les deux vues sont mutuellement exclusives.
- Poser les fondations (modèle `Gathering`) pour les fonctionnalités à venir (ODJ, décisions, rappels) sans les implémenter.

## Decisions & rationale

| Décision | Raison |
|---|---|
| Nouveau modèle `Gathering` (pas de réutilisation d'`Event`) | `Event` reste disponible pour un futur module "événements externes". Les deux flux ont des exigences différentes (ODJ, décisions à venir pour gathering). |
| `GatheringCategory` en table (pas enum) | Permet au collectif d'ajouter/modifier des catégories sans migration ni déploiement. |
| Pas de récurrence native | Le gardien "va à la pêche aux dates" — les occurrences ne sont jamais purement mécaniques. Quick-create 2-clics suffit. |
| Switch exclusif Réservations/Organisation | Garde chaque vue lisible. Un sourcier qui cherche une date libre bascule rapidement. |
| Switch via URL param (`?view=organisation`) | Partageable, bookmarkable, pas de préférence utilisateur à persister. |
| CRUD catégories ouvert à tous | Collectif de 8 personnes, faible risque de prolifération ; cohérent avec l'esprit gouvernance partagée. |
| Pas d'intégration dashboard/`/organisation` | Reporté au chantier 2 où la préparation prend tout son sens. |

## Architecture

### Modèles

**`GatheringCategory`**

| Champ | Type | Obligatoire | Note |
|---|---|---|---|
| `name` | string | ✓ | ex. "PUD" |
| `color` | string | ✓ | nom Tailwind (ex. "emerald") |
| `default_start_time` | time | | nullable = "variable" |
| `default_duration_minutes` | integer | | nullable = "variable" |
| `deleted_at` | datetime | | soft-deletion |

- `has_many :gatherings, dependent: :nullify`
- `has_paper_trail`, `has_soft_deletion default_scope: true`
- Validation : `name`, `color` présents ; `default_duration_minutes > 0` si présent.

**`Gathering`**

| Champ | Type | Obligatoire | Note |
|---|---|---|---|
| `name` | string | | fallback "#{category.name} du #{date}" |
| `gathering_category_id` | FK | ✓ | |
| `starts_at` | datetime | ✓ | |
| `ends_at` | datetime | ✓ | |
| `location` | string | | libre ("salle commune", "visio"…) |
| `notes` | rich text | | via ActionText |
| `deleted_at` | datetime | | soft-deletion |

- `belongs_to :gathering_category`
- `has_rich_text :notes`
- `has_paper_trail`, `has_soft_deletion default_scope: true`, `include PublicActivity::Model` + `tracked`
- Validation : `ends_at >= starts_at`
- Scope : `by_star_field :starts_at, :ends_at` (expose `between_times` pour le calendrier)
- Index : `[starts_at, ends_at]`
- `attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time` (split pour le form, pattern existant de `Event`)

### Routes

```ruby
resources :gathering_categories
resources :gatherings do
  collection do
    post :quick_create
  end
end
```

### Contrôleurs

**`GatheringCategoriesController`** : CRUD clone de `EventCategoriesController`. Accessible à tout utilisateur authentifié.

**`GatheringsController`** : CRUD clone de `EventsController`, plus l'action `quick_create` :
- Lit `params[:category_id]` et `params[:date]`
- Compose `starts_at = date + category.default_start_time` (ou 00:00 si nil)
- `ends_at = starts_at + (category.default_duration_minutes || 60).minutes`
- Deux cas :
  - **Catégorie à horaires connus** : persiste puis répond en Turbo Stream (`append` sur `day_gatherings_#{date}`) — la barre apparaît sans reload.
  - **Catégorie "variable"** (horaires nuls) : persiste avec fallback 12:00 / 60min et répond par `turbo_stream.redirect` (ou `Turbo.visit` via header) vers `edit_gathering_path` pour forcer la saisie des heures.

**`PagesController#calendar`** : ajoute une branche selon `params[:view]` :
```ruby
@calendar_view = params[:view] == "organisation" ? :organisation : :bookings
if @calendar_view == :organisation
  @gatherings = GatheringDecorator.decorate_collection(
    Gathering.includes(:gathering_category).between_times(@first, @last)
  )
  @gathering_categories = GatheringCategory.ordered
end
# branche bookings inchangée
```

### Vues

**Modifications**
- `app/views/pages/calendar.html.slim` : branchement `@calendar_view` ; le `page_header` reçoit un partial `_view_toggle` avant les boutons de navigation mensuelle.

**Nouveaux partials (calendrier)**
- `app/views/pages/calendar/_view_toggle.html.slim` : deux onglets (Réservations | Organisation), préservant `start_date`.
- `app/views/pages/calendar/_organisation.html.slim` : rend `SimpleCalendar::DashboardCalendar` avec cellule jour custom :
  1. Numéro du jour
  2. `turbo_frame_tag "day_gatherings_#{date.iso8601}"` contenant les barres des `@gatherings` couvrant ce jour
  3. `_quick_create_button` (bouton + dropdown de catégories)
- `app/views/pages/calendar/_gathering.html.slim` : une barre — pastille couleur, horaire si premier jour, nom affiché. Popover au hover.
- `app/views/pages/calendar/_quick_create_button.html.slim` : `+` + menu dropdown Stimulus, chaque item = `button_to quick_create_gatherings_path(category_id:, date:), method: :post, form: { data: { turbo_stream: true } }`.
- `app/views/gatherings/quick_create.turbo_stream.slim` : append sur `day_gatherings_#{date}`.

**CRUD complet**
- `app/views/gatherings/` : `index`, `show`, `new`, `edit`, `_form`, `_popover` (clonés de `events/` en retirant `url`, `attendees`, `sales_amount`, `status` ; en ajoutant `location`).
- `app/views/gathering_categories/` : `index`, `show`, `new`, `edit`, `_form` (clonés de `event_categories/` + champs `default_start_time` et `default_duration_minutes`).

### Décorateur

`app/decorators/gathering_decorator.rb` (inspiré d'`EventDecorator`) :
- `display_name` : `name.presence || "#{gathering_category.name} du #{h.l(starts_at.to_date)}"`
- `calendar_class` : classes Tailwind dynamiques depuis `gathering_category.color` (ex. `"border-l-4 border-#{color}-500 bg-#{color}-50"`)
- `time_range` : horaire humain, différenciant mono-jour vs multi-jours
- `color_dot` : `bg-#{color}-300`
- `popover_body` : catégorie, horaire, lieu, extrait `notes.body.to_plain_text` (100 chars)
- `decorates_association :gathering_category`

### Stimulus

Réutilisation du `dropdown_controller` existant pour le menu quick-create. Réutilisation de `popover_controller` pour les popovers au hover sur les barres. Aucun nouveau contrôleur Stimulus à écrire.

### Tailwind safelist

Ajouter dans `tailwind.config.js` les tokens suivants pour chaque teinte utilisée par les catégories (initialement : emerald, amber, violet, rose, sky — et toutes les teintes Tailwind si on veut du futur-proof) :
- `border-#{color}-500`
- `bg-#{color}-50`

La safelist actuelle couvre déjà `bg-*-300`.

### Seeds

Dans `db/seeds.rb`, append idempotent avec `find_or_create_by!(name:)` :

| Nom | Couleur | default_start_time | default_duration_minutes |
|---|---|---|---|
| PUD | emerald | 08:45 | 360 |
| Chantier | amber | 09:30 | 480 |
| Conseil des Sourciers | violet | 18:00 | 60 |
| Mise au vert | rose | 00:00 | 1440 |
| Rencontre archis | sky | nil | nil |

## Flow de données (quick-create)

1. Sourcier navigue sur `/?view=organisation&start_date=2026-05-01`
2. Hover sur la cellule du jeudi 12 mai → bouton `+` visible
3. Clic sur `+` → dropdown affiche les 5 catégories
4. Clic sur "PUD" → `POST /gatherings/quick_create?category_id=1&date=2026-05-12` (Turbo Stream)
5. Serveur : crée `Gathering(category: PUD, starts_at: 2026-05-12 08:45, ends_at: 2026-05-12 14:45)`
6. Réponse Turbo Stream `append` → la barre apparaît dans `day_gatherings_2026-05-12`
7. Sourcier peut cliquer la barre pour ouvrir `/gatherings/:id/edit` et ajuster.

## Build sequence

1. **Migrations** : `gathering_categories`, `gatherings` + index.
2. **Modèles** : `Gathering`, `GatheringCategory` avec associations, soft-delete, paper_trail, rich text, public_activity. Test en `rails console`.
3. **Seeds** : ajout des 5 catégories, `rails db:seed`.
4. **Tailwind safelist** : ajouter les tokens `border-*-500` et `bg-*-50` pour emerald/amber/violet/rose/sky.
5. **CRUD `GatheringCategory`** : controller + views + services. Test via `/gathering_categories`.
6. **CRUD `Gathering`** (form complet) : controller + views + services. Test via `/gatherings/new`.
7. **`GatheringDecorator`** + `_popover`.
8. **Switch calendar** : `PagesController#calendar` branche + `_view_toggle` + `_organisation` rendant les barres multi-jours.
9. **Quick-create** : action `quick_create`, route, `_quick_create_button`, `quick_create.turbo_stream.slim`.
10. **Polish** : blank state ("Aucun moment ce mois-ci"), accessibility dropdown, hover states.

Chaque étape est indépendamment vérifiable.

## Verification (bout en bout)

- `/gathering_categories` : créer / éditer / soft-delete une catégorie.
- `/gatherings/new` : créer un gathering avec nom, heures, lieu, notes rich text. Vérifier `show`.
- `/?view=organisation&start_date=<mois>` : barre rendue aux bons jours avec la couleur de catégorie.
- Créer une "Mise au vert" sur 3 jours → la barre s'étend sur 3 cellules.
- Clic `+` sur un jour → menu catégories → clic "PUD" → barre apparaît via Turbo Stream sans reload, heure 08:45, durée 6h.
- Clic sur la barre → page edit, modifier nom + heures → retour calendrier, changements visibles.
- Soft-delete un gathering depuis `show` → disparaît du calendrier et de `/gatherings`.
- Toggle `?view=bookings` → retour à la vue actuelle, aucun gathering visible, bookings/space_bookings intacts.
- `gathering.versions.count > 0` après update (paper_trail).
- Activity feed (vue Réservations) non cassé.

## Critical files

- **Modifiés** :
  - [config/routes.rb](config/routes.rb)
  - [app/controllers/pages_controller.rb](app/controllers/pages_controller.rb)
  - [app/views/pages/calendar.html.slim](app/views/pages/calendar.html.slim)
  - [db/seeds.rb](db/seeds.rb)
  - [tailwind.config.js](tailwind.config.js)
- **Créés** :
  - `app/models/gathering.rb`, `app/models/gathering_category.rb`
  - `app/controllers/gatherings_controller.rb`, `app/controllers/gathering_categories_controller.rb`
  - `app/decorators/gathering_decorator.rb`, `app/decorators/gathering_category_decorator.rb`
  - `app/services/gatherings/`, `app/services/gathering_categories/`
  - `app/views/gatherings/` (clonés/adaptés de `app/views/events/`)
  - `app/views/gathering_categories/` (clonés/adaptés de `app/views/event_categories/`)
  - `app/views/pages/calendar/_view_toggle.html.slim`
  - `app/views/pages/calendar/_organisation.html.slim`
  - `app/views/pages/calendar/_gathering.html.slim`
  - `app/views/pages/calendar/_quick_create_button.html.slim`
  - Migrations : `create_gathering_categories`, `create_gatherings`
- **Références (clone/inspiration, non modifiés)** :
  - [app/models/event.rb](app/models/event.rb), [app/models/event_category.rb](app/models/event_category.rb)
  - [app/controllers/events_controller.rb](app/controllers/events_controller.rb), [app/controllers/event_categories_controller.rb](app/controllers/event_categories_controller.rb)
  - [app/decorators/event_decorator.rb](app/decorators/event_decorator.rb)

## Non-goals (reportés au chantier 2)

- ODJ (agenda items) et docs de préparation par gathering.
- Traçabilité des décisions (modèle `Decision`, PV).
- Rappels automatiques (préparation, présence, souper).
- Présences / participants.
- Récurrence (même simple).
- Widget dashboard "Mes prochains moments".
- Intégration dans la section `/organisation`.
- Rôle "Gardien des plannings" (permissions, assignations) — pour l'instant tout sourcier authentifié peut tout faire.
- Refactor de `PagesController#calendar` (déjà chargé, mais hors périmètre).
