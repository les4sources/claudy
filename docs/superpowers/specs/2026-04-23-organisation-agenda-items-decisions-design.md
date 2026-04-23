# Organisation — ODJ et Décisions (chantier 2)

**Date** : 2026-04-23
**Statut** : Design validé, en cours d'implémentation
**Chantier précédent** : [2026-04-23-agenda-organisation-view-design.md](2026-04-23-agenda-organisation-view-design.md) (vue Organisation du calendrier, modèle `Gathering`)

## Context

Le chantier 1 a introduit les `Gathering` (moments collectifs : PUD, chantiers, conseils, mises au vert, rencontres archis) et leur vue calendrier. Ce chantier 2 outille la **préparation** et la **mémoire** de ces moments — ce que le rôle "Gardien des plannings et ODJ" décrit dans son cahier des charges :

- **Ordres du jour** (ODJ) à alimenter en amont des rendez-vous par tout sourcier
- **Fiches de préparation** par point d'ODJ (rich text + pièces jointes)
- **Registre des décisions** consignées, recherchable, pour faire référence quand les débats vacillent

Hors périmètre : rappels automatiques, présences/RSVP (chantier 3+).

## Objectifs

- Chaque `Gathering` peut porter un ODJ structuré, alimenté collaborativement.
- Chaque point d'ODJ a une fiche de prépa (rich text + attachments) et peut être réordonné via drag & drop.
- Les décisions prises sont consignées dans un registre autonome, attachables à un gathering et/ou un point d'ODJ, recherchable en texte libre.
- La page `/organisation` devient un dashboard : prochain moment + son ODJ + décisions récentes + humains du cycle.

## Decisions & rationale

| Décision | Raison |
|---|---|
| `AgendaItem` = titre + rich text description + author + completed | Correspond au vocabulaire du cahier des charges ("point" + "fiche de préparation d'un point"). |
| Auteur tracké mais édition libre pour tous | Gouvernance partagée, 8 personnes, PaperTrail couvre les abus. |
| ODJ sur tous les gatherings (pas de distinction catégorie) | Même un chantier peut avoir un ODJ ("actions de chantier", "thèmes des chantiers à thèmes"). Section cachée si vide. |
| `Decision` séparée avec `gathering_id` / `agenda_item_id` optionnels | Permet décisions hors-gathering (urgences, décisions par mail). |
| Pas de statut sur `Decision` | YAGNI ; une révision se matérialise par une nouvelle décision. |
| `recorded_by` auto-rempli, pas de `proposed_by` | Traçabilité utile, co-construction rend `proposed_by` flou. |
| Recherche full-text simple (ILIKE) | Volume faible (dizaines de décisions par an), pas besoin de PG full-text. |
| Drag & drop immédiat via SortableJS | Demandé explicitement. Ajoute un Stimulus controller + `position`. |
| Rich text + Active Storage sur `AgendaItem.description` | ActionText gère déjà l'upload dans Trix ; pièces jointes = demandé. |

## Architecture

### Modèles

**`AgendaItem`**

| Champ | Type | Obligatoire |
|---|---|---|
| `gathering_id` | FK | ✓ |
| `author_id` | FK (→ Human) | ✓ |
| `title` | string | ✓ |
| `description` | rich text | — |
| `position` | integer | ✓ (défaut 0, auto-calculé) |
| `completed` | boolean | ✓ (défaut false) |
| `deleted_at` | datetime | — |

- `belongs_to :gathering`
- `belongs_to :author, class_name: "Human"`
- `has_many :decisions, dependent: :nullify`
- `has_rich_text :description`
- `has_paper_trail`, `has_soft_deletion default_scope: true`, `include PublicActivity::Model` + `tracked`
- Scope : `ordered` (par `position` croissant)
- Before create : `position ||= (gathering.agenda_items.maximum(:position) || -1) + 1`

**`Decision`**

| Champ | Type | Obligatoire |
|---|---|---|
| `title` | string | ✓ |
| `summary` | string | ✓ (une phrase scannable) |
| `body` | rich text | — |
| `taken_at` | date | ✓ |
| `recorded_by_id` | FK (→ Human) | ✓ |
| `gathering_id` | FK | — |
| `agenda_item_id` | FK | — |
| `deleted_at` | datetime | — |

- `belongs_to :recorded_by, class_name: "Human"`
- `belongs_to :gathering, optional: true`
- `belongs_to :agenda_item, optional: true`
- `has_rich_text :body`
- `has_paper_trail`, `has_soft_deletion default_scope: true`, `include PublicActivity::Model` + `tracked`
- Scopes : `recent` (order taken_at desc), `search(query)` (ILIKE sur title/summary + ActionText body via join)

### Modifications au modèle `Gathering`

- `has_many :agenda_items, dependent: :destroy`
- `has_many :decisions, dependent: :nullify`

### Migrations

1. `create_agenda_items` : les champs ci-dessus + indexes sur `[gathering_id, position]`, FKs.
2. `create_decisions` : les champs + indexes sur `taken_at desc`, FKs avec `on_delete: :nullify` pour gathering/agenda_item.

### Routes

```ruby
resources :gatherings do
  resources :agenda_items, except: [:index, :show] do
    member do
      patch :toggle_completed
    end
    collection do
      patch :reorder
    end
  end
end
resources :decisions
get "organisation/decisions", to: "decisions#index"  # alias
```

### Contrôleurs

**`AgendaItemsController`** (nested sous gathering)
- `new`, `create`, `edit`, `update`, `destroy` — CRUD standard
- `toggle_completed` — flip le booléen, Turbo Stream
- `reorder` — reçoit un array d'ids dans le nouvel ordre, met à jour `position` en batch
- L'auteur est `current_user.human`

**`DecisionsController`**
- `index` — registre : recherche via `params[:q]` (ILIKE)
- `new`, `create`, `edit`, `update`, `show`, `destroy`
- `recorded_by` = `current_user.human` auto-rempli au create (non-éditable)

**`OrganisationController#index`** modifié pour charger :
- `@next_gathering` = `Gathering.upcoming.first` (déjà défini en scope)
- `@upcoming_gatherings_count` (pour stat)
- `@recent_decisions = Decision.recent.limit(5)`

### Vues

**Nouveaux partials**
- `app/views/agenda_items/` : `_form.html.slim`, `_item.html.slim` (rendu d'un point dans la liste), `new.html.slim`, `edit.html.slim`
- `app/views/agenda_items/create.turbo_stream.slim` (append + reset form)
- `app/views/agenda_items/destroy.turbo_stream.slim` (remove)
- `app/views/agenda_items/toggle_completed.turbo_stream.slim` (replace)
- `app/views/decisions/` : `index`, `show`, `new`, `edit`, `_form`, `_decision.html.slim` (rendu dans liste)
- `app/views/organisation/_next_moment_card.html.slim` (dashboard `/organisation`)
- `app/views/organisation/_recent_decisions_card.html.slim`

**Modification `app/views/gatherings/show.html.slim`**
- Ajout d'une section "Ordre du jour" avec liste des AgendaItems + formulaire inline "+ Ajouter un point"
- Ajout d'une section "Décisions prises" (si le gathering a des décisions)
- Turbo Frame pour la liste des items (`turbo_frame_tag "agenda_items_#{@gathering.id}"`)
- Drag & drop via Stimulus controller `sortable`

**Modification `app/views/organisation/index.html.slim`**
- Ajout en haut : grille de 3 cartes (next_moment, recent_decisions, cycle actuel)
- Section existante (humains + cycle_actions) reste en dessous

### Décorateurs

- `AgendaItemDecorator` — couleur d'état (completed ou pas), auteur formaté, extrait description
- `DecisionDecorator` — date formatée, preview body, liens vers gathering/agenda_item

### Stimulus

- `sortable_controller.js` — wrapper SortableJS : au drop, envoie un PATCH vers `reorder` avec la liste d'ids. Utilise `fetch` avec CSRF token.
- Installer SortableJS : `yarn add sortablejs`

### Dépendances & outillage

- **SortableJS** (~30kb min+gzip) pour le drag & drop des points d'ODJ
- **ActionText/Trix** — déjà en place, utilisé pour description des items et body des décisions
- **Active Storage** — déjà en place, utilisé via ActionText pour les attachments

### Tailwind

Pas de couleur dynamique nouvelle. La safelist du chantier 1 couvre déjà tout.

## Flow utilisateur

**Ajouter un point à l'ODJ du prochain PUD depuis `/organisation` :**
1. Sourcier arrive sur `/organisation`, voit la carte "Prochain moment : PUD du 14 mai"
2. Champ inline "+ Ajouter un point" visible directement
3. Saisit "budget chauffage", envoie (Turbo Stream append)
4. Point apparaît dans la liste, auteur = lui, position = dernière

**Rédiger la fiche de prépa :**
1. Clic sur le point → page `/gatherings/:id`
2. Section ODJ affiche le point, clic "Éditer" → form avec rich text Trix + Active Storage
3. Rédaction + drop d'un PDF "Budget 2026"
4. Sauvegarde → retour à la page show

**Consigner une décision :**
1. Pendant/après le PUD, sourcier clique "+ Consigner une décision" sur la page show du gathering
2. Form prérempli avec `gathering_id` et date = aujourd'hui, `recorded_by` = soi
3. Saisit titre + résumé + body, éventuellement lie à un point d'ODJ précis
4. Sauvegarde → décision apparaît sur la page show + dans le registre global

**Rechercher une décision ancienne :**
1. `/organisation/decisions`
2. Champ de recherche `q` → ILIKE sur title + summary + plain_text du body
3. Résultats triés par `taken_at desc`

## Build sequence

1. **Migrations** : `agenda_items` puis `decisions`
2. **Modèles** : `AgendaItem` + `Decision` (associations, soft-delete, PaperTrail, validations). Ajouter `has_many` sur `Gathering`. Smoke test.
3. **AgendaItem CRUD** : controller + services + form + partial `_item` rendu dans une liste sur la page show du gathering. Pas encore de drag&drop.
4. **Turbo Stream** : create (append), destroy (remove), toggle_completed (replace).
5. **SortableJS + drag&drop** : yarn add, Stimulus `sortable_controller`, action `reorder` batch update.
6. **Decision CRUD** : controller + services + views. Registre `/organisation/decisions` avec recherche ILIKE.
7. **Intégration `/organisation`** : cartes "Prochain moment" (avec ODJ inline + ajout rapide) + "Décisions récentes".
8. **Intégration `/gatherings/:id`** : sections ODJ + Décisions.
9. **Polish** : blank states, accessibility drag&drop (keyboard fallback si temps), CSS attachments.

## Verification

- Créer des points d'ODJ sur un gathering, vérifier position auto + auteur auto.
- Toggle completed, vérifier le Turbo Stream.
- Drag & drop 3 points, recharger la page → ordre conservé.
- Ajouter attachment (PDF) dans la fiche de prépa, vérifier qu'il est téléchargeable.
- Créer une décision liée à un point d'ODJ, apparaît sur la page gathering ET dans `/organisation/decisions`.
- Recherche "budget" dans `/organisation/decisions` trouve la décision contenant ce mot dans le body.
- `/organisation` affiche la carte "Prochain moment" avec compteur ODJ + les 5 dernières décisions.
- Soft-delete un item → disparaît. PaperTrail conservé.
- Vérifier que déléguer une décision à un agenda_item supprimé ne casse rien (`on_delete: :nullify`).

## Critical files

**Modifiés** :
- [app/models/gathering.rb](app/models/gathering.rb) (ajout `has_many :agenda_items, :decisions`)
- [app/views/gatherings/show.html.slim](app/views/gatherings/show.html.slim)
- [app/controllers/organisation_controller.rb](app/controllers/organisation_controller.rb)
- [app/views/organisation/index.html.slim](app/views/organisation/index.html.slim)
- [config/routes.rb](config/routes.rb)

**Créés** :
- `app/models/agenda_item.rb`, `app/models/decision.rb`
- `app/controllers/agenda_items_controller.rb`, `app/controllers/decisions_controller.rb`
- `app/decorators/agenda_item_decorator.rb`, `app/decorators/decision_decorator.rb`
- `app/services/agenda_items/`, `app/services/decisions/` (create/update services)
- `app/views/agenda_items/`, `app/views/decisions/`
- `app/frontend/controllers/sortable_controller.js`
- Migrations : `create_agenda_items`, `create_decisions`

## Non-goals (chantier 3+)

- Rappels automatiques (mail/notif aux sourciers avant un gathering)
- Présences / RSVP
- Tags sur les décisions
- Statut (révisée/annulée) sur les décisions
- Filtres avancés dans le registre
- Export PDF d'un PV
- Rôle "Gardien" explicite avec permissions
