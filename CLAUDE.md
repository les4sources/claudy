# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claudy is an in-house web app for Les 4 Sources (foundation in Yvoir, Belgium). Manages bookings, lodgings, spaces, humans, cycles, and payments for the Domaine d'Ahinvaux.

Stack: Rails 7.0 · Ruby 3.1.2 · PostgreSQL · Node 18.8.0 · Vite (via `vite_rails`) · Hotwire (Turbo + Stimulus) · Tailwind · Slim · Devise · Stripe · Postmark · Sentry.

## Common commands

- `bin/dev` — run app + Vite (foreman, Procfile.dev). Vite serves on port 3000 per `vite.config.ts`.
- `rails s` / `bin/vite dev` — run the two processes separately.
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
- **Public namespace** (`namespace :public`) is the guest-facing (token-based) booking/payment flow; everything outside it requires Devise auth.
- **Stripe webhooks** land at `webhooks/stripe_hooks#create`; `StripeEvent` model persists them.
- **Calendar** uses the `simple_calendar` gem with custom overrides in `app/calendars/simple_calendar/`. The root route `pages#calendar` is the primary UI.
- **Vite full-reload** is configured to watch `config/routes.rb`, views, components, and locale YAMLs (see `vite.config.ts`).
- **Soft deletion** (`soft_deletion` gem) and **PaperTrail** versioning are in use — prefer these over hard destroys for auditable records.
- **Authorization** relies on Devise + role models (`Role`, `HumanRole`); no Pundit/CanCan — check controller-level `before_action` patterns.
- `nio4r` needs `--with-cflags="-Wno-incompatible-pointer-types"` on macOS Sequoia (see README Quick Start).

## Deployment

Hatchbox → Linode VPS. Production DB is PostgreSQL. No staging environment.
