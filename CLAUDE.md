# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claudy is an in-house web app for Les 4 Sources (foundation in Yvoir, Belgium). Manages bookings, lodgings, spaces, humans, cycles, and payments for the Domaine d'Ahinvaux.

Stack: Rails 8.1 · Ruby 3.4.10 · PostgreSQL · Node 18.8.0 · Vite (via `vite_rails`) · Hotwire (Turbo + Stimulus) · Tailwind · Slim · Devise · Stripe · Postmark · Sentry.

## Common commands

- `bin/dev` — runs **Vite only** (foreman, `Procfile.dev` contains just `vite: bin/vite dev`). It does *not* start Rails.
- `rails s` — the app, on port 3000. Always needed alongside `bin/dev` (or `bin/vite dev`).
- Vite dev listens on port 3036 per `config/vite.json`; dev assets are auto-built into `public/vite-dev/` when no Vite process runs.
- `rails db:create && rails db:migrate && rails db:seed` — bootstrap DB (seeds lodgings/rooms/spaces).
- `bundle exec rspec` — run tests (RSpec; specs live in `spec/`, currently only `models/` and `components/`).
- `bundle exec rspec spec/models/booking_spec.rb:42` — run a single test.
- `bin/sync-production-database` — dumps prod DB via SSH and restores into `claudy_development` (uses Postgres.app 15 binaries, hardcoded SSH host).
- `/lookbook` — ViewComponent preview UI, mounted in development only.

## Architecture notes

- **Decorators (Draper)** wrap models for view logic — `app/decorators/*_decorator.rb`. Prefer adding presentation logic here over helpers or model methods.
- **ViewComponent + Lookbook** for reusable UI — `app/components/` with previews browsable at `/lookbook`. Presenters for components live in `app/presenters/components/`.
- **Services** — `app/services/<resource>/` holds resource-specific service objects (e.g. `bookings/`, `booking_prices/`, `cycle_actions/`).
- **Slim** is the template engine — views are `.html.slim`, not `.erb`.
- **Listes déroulantes = toujours cherchables** (Michael, 2026-09-30) : tout choix dans une liste passe par le contrôleur Stimulus `searchable-select` (`app/frontend/controllers/searchable_select_controller.js`) posé sur le `<select>`, avec le champ de recherche `shared/_searchable_select_search`. Jamais de `<select>` nu. Le `<select>` reste la source de vérité soumise par le formulaire ; `data-searchable-select-clearable-value="true"` pour un choix facultatif.
- **Public namespace** (`namespace :public`) is the guest-facing (token-based) booking/payment flow; everything outside it requires Devise auth.
- **Stripe webhooks** land at `webhooks/stripe_hooks#create`; `StripeEvent` model persists them.
- **Calendar** uses the `simple_calendar` gem with custom overrides in `app/calendars/simple_calendar/`. The root route `pages#calendar` is the primary UI.
- **Vite full-reload** is configured to watch `config/routes.rb`, views, components, and locale YAMLs (see `vite.config.ts`).
- **Soft deletion** (`soft_deletion` gem) and **PaperTrail** versioning are in use — prefer these over hard destroys for auditable records.
- **Authorization** relies on Devise + role models (`Role`, `HumanRole`); no Pundit/CanCan — check controller-level `before_action` patterns.
- **Tranches de Vie** (issue #339) — `TranchesDeVie::Client` lit l'API de l'app de la boulangerie (`TRANCHESDEVIE_API_URL`, `TRANCHESDEVIE_API_KEY`) pour rattacher une Pizza Party payée à un séjour. Lecture seule, jamais d'écriture sortante ; sans clé le client est `configured? == false` et l'UI désactive le bouton au lieu d'échouer.
- **Panneau de la carte** (Michael, 2026-10-03) : deux onglets (`map_panel_controller.js`). « Travailler » = la couche active (une seule, réseaux compris) et, sous elle, ses actions (`data-layer-extra`) ; « Afficher » = fond, relief, Géoportail replié par groupe, filtres. Les pages annexes sont en pied de panneau, jamais dans les sections. Un nouvel élément va dans l'un de ces trois endroits.
- **Pl@ntNet** — `PlantNet::Client` identifie une plante à partir de 1 à 5 photos (fiche plante de la carte, « Identifier l'espèce par photo »). Jev ne lit pas d'images : c'est Pl@ntNet qui propose les espèces, rapprochées du catalogue par `PlantNet::Identify` ; l'humain valide ou refuse. Sans `PLANTNET_API_KEY`, le bouton est désactivé.
- **Serveur MCP** (Michael, 2026-10-05) — `POST /mcp` (`Mcp::ServerController` → `Mcp::Server`), outils métier dans `app/services/mcp/tools/` (un sous-dossier par domaine, ex. `sejours/`, qui appelle les mêmes services que les écrans), serveur OAuth maison (`Mcp::OauthController`, `Mcp::AuthorizationsController`, tables `mcp_*`). Un outil qui écrit hérite de `Mcp::Tools::Ecriture` : aperçu d'abord, confirmation signée ensuite, PaperTrail `claude:<e-mail> — <motif>`. Jamais d'outil qui exécute du code ou du SQL libre. Accès : `MCP_ALLOWED_EMAILS`.
- `nio4r` needs `--with-cflags="-Wno-incompatible-pointer-types"` on macOS Sequoia (see README Quick Start).

## Deployment

Hatchbox → Linode VPS. Production DB is PostgreSQL. No staging environment.
