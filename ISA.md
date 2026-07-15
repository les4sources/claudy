---
project: Claudy
task: "Project ISA — Claudy"
effort: e3
effort_source: explicit
phase: observe
progress: 0/15
mode: interactive
started: 2026-05-28T00:00:00Z
updated: 2026-05-28T00:00:00Z
---

## Problem

Les 4 Sources combine deux activités quotidiennes très différentes — l'hospitalité commerciale (gîtes, salles, épicerie, bar) et la vie d'un collectif de 5 familles + 8 membres présents 2 jours/semaine sur 15 hectares. Avant Claudy, ces deux mondes vivaient dans des outils éclatés (tableurs, Stripe en standalone, agenda papier pour les cycles du collectif), et la connaissance opérationnelle se perdait à chaque transmission. Côté hospitalité, le flux invité (devis → réservation → paiement Stripe) n'avait pas de maison unique ; côté collectif, le suivi des cycles, des cycle-actions et des décisions n'était nulle part centralisé. Il manquait aussi un canal lisible pour qu'un agent IA (Bee et les futurs agents internes du domaine) puisse interroger l'état du domaine sans gratter l'UI.

## Vision

Claudy est à la fois la **mémoire opérationnelle** et l'**outil de gestion quotidienne** des 4 Sources. Le Pôle Accueil ouvre une seule page — le calendrier — et voit l'intégralité de l'activité économique du domaine : qui arrive, qui part, quels gîtes/chambres/salles sont réservés, quelles activités sont portées par qui (membre du collectif au tarif unique, ou prestataire externe au tarif négocié), quels paiements sont en attente, quels événements approchent. Quand un client compose son séjour aux 4 Sources, Claudy en tient la **composition complète** : hébergement + activités + buffet + pain (boulangerie tranches-de-vie) + options de salle (ex. sono) + événements, vu comme **un seul panier** — pas comme des réservations séparées. Côté collectif, c'est aussi là que vivent les cycles, les cycle-actions, les agendas et les décisions. Côté agent IA, Bee interroge le domaine sans ouvrir l'UI.

**Surprise euphorique** : un client compose son séjour des 4 Sources comme un panier — gîte du vendredi au dimanche + atelier soudure le samedi + buffet le samedi soir + pain frais le dimanche matin — paye en un seul Stripe Checkout, reçoit un email récapitulatif, et arrive le vendredi sans qu'aucun humain n'ait eu à orchestrer les morceaux. Et le lundi matin où le Pôle Accueil ouvre Claudy à 8h, ils voient toute la semaine sur une seule page — incluant l'agenda de la prochaine réunion du collectif jeudi.

## Out of Scope

- Pas d'app mobile **côté staff** (Pôle Accueil, collectif, freelances) — l'UI web responsive Tailwind suffit pour les opérationnels. **NB :** une app mobile **côté client** pour les invités en séjour est dans l'ideal state (cf. Feature `GuestMobileApp` plus bas) — c'est l'app staff qui reste web-only.
- Pas de multi-tenant : Claudy sert Les 4 Sources et personne d'autre. Ce n'est pas un SaaS de tiers-lieux.
- Pas de marketplace / découverte publique : les invités arrivent par lien-token, pas par recherche moteur.
- Pas d'auth tierce (Google/SSO) : Devise + jeton API, point.
- Pas d'écriture via l'API agents en v1 — `GET` uniquement.
- Pas de staging environment — un seul environnement prod sur Hatchbox.
- Pas de remplacement de la **comptabilité formelle de la fondation** — celle-ci vit dans **Winbooks** (factures fiscales, déclarations TVA, exports comptables, bilans). Claudy **facilite** la gestion comptable en enregistrant proprement dépenses, recettes et paiements pour que ces données nourrissent Winbooks, mais n'est pas un logiciel comptable légal.

**Note de portée évolutive** — le scope ÉVOLUE dans le temps. La v1 livrée aujourd'hui couvre hospitalité + flow public + organisation collective + API agent. L'ideal state vise l'intégration progressive de : (a) **activités** payantes portées par membres (tarif horaire collectif) ou prestataires (tarif négocié) — modèles `Experience`/`Service` partiellement en place, (b) **événements** récurrents ou one-shot (remplacement de BilletWeb) — modèle `Event` partiellement en place, (c) **bar** (boissons/chips, aujourd'hui virement/cash), (d) **épicerie** (productions micro-ferme + vrac, aujourd'hui virement/cash), (e) **intégration boulangerie tranches-de-vie** comme service additionnel d'un séjour, (f) **tracking budgétaire par Pôle** (dépenses + recettes par pôle, lisibles par chaque pôle) — modèle `Team` en place sans champs financiers. Aucune de ces évolutions n'effacera les contraintes Out of Scope ci-dessus.

## Constraints

- **Stack figé** : Rails 7.0 + Ruby 3.1.2 + PostgreSQL + Node 18.8.0 + Vite (`vite_rails`). Pas de migration vers Rails 8 dans ce périmètre.
- **Hotwire** (Turbo + Stimulus) — pas de React, Vue ou Inertia. Le récent travail de migration loin de Flowbite a renforcé cette ligne (commits récents : Stimulus controllers à la place de Flowbite JS).
- **Slim** comme moteur de templates (pas ERB).
- **Devise + role models** (`Role`, `HumanRole`) pour l'autorisation — pas de Pundit/CanCan, les contrôles vivent dans les `before_action` controller.
- **Soft deletion** (`soft_deletion` gem) + **PaperTrail** sur les records auditables — pas de `destroy` durs.
- **Décorateurs Draper** pour la logique de vue (`app/decorators/*_decorator.rb`).
- **ViewComponent + Lookbook** pour l'UI réutilisable, présentateurs dans `app/presenters/components/`.
- **Services** organisés par ressource sous `app/services/<resource>/`.
- **Déploiement Hatchbox** → VPS Linode 2GB, pas de staging.
- **Postmark** pour les emails sortants, **Stripe** pour les paiements, **Sentry** pour la télémétrie.
- **`nio4r`** nécessite `--with-cflags="-Wno-incompatible-pointer-types"` sur macOS Sequoia (cf. README).
- **Claudy est la source de vérité du planning — les OTAs sont des clones aval.** Airbnb, Booking.com et tout futur canal externe synchronisent leur calendrier *depuis* Claudy (sync sortante). Les réservations entrantes depuis un OTA viennent enrichir Claudy mais ne lui *imposent* jamais l'état du planning. Motivation : l'analyse inbox 2026-05-28 a documenté des cas de **désynchronisation OTA ↔ planning interne** avec risque de double-booking permanent (Airbnb laisse passer une réservation alors que le gîte est déjà loué côté Pôle Accueil) — la seule prévention est un master unique.
- **Calendrier de disponibilités ouvert à +18 mois.** Les mariages se demandent 6-18 mois à l'avance, les mises au vert et retraites scolaires 3-9 mois, les "options pré-réservation" 2-12 mois. Toute fenêtre <18 mois rate du CA. Conséquence : génération de slots futurs + gestion d'options posées par Malau (industrialiser le pattern manuel actuel).
- **Lodging supporte la composition.** Le modèle `Lodging` doit gérer le pattern *unité physique* vs *composition réservable* — exemple concret : Le Grand-Duc = La Hulotte + La Chevêche. Réserver une composition bloque automatiquement ses sous-unités et inversement. À implémenter via une self-referential association (ex. `composed_of_lodgings`) plutôt que de dupliquer des données ou de créer un faux 3e gîte.
- **Résilience offline obligatoire pour le bar et l'épicerie.** Les coupures internet sont une réalité aux 4 Sources. Les surfaces de vente sur place (kiosk bar, kiosk épicerie connecté à la balance, scan mobile guest) doivent dégrader proprement : soit transaction queue locale qui se synchronise à la reconnexion sans perte, soit fallback explicite vers le **carnet papier** qui reste la source de vérité de dernier recours. Aucune transaction sur place ne doit pouvoir échouer "silencieusement" à cause d'un réseau coupé.

## Goal

Opérer la totalité de la vie économique et associative des 4 Sources depuis une seule app Rails, avec six surfaces stables : (1) une **UI calendrier-first** authentifiée Devise pour le Pôle Accueil + le collectif, (2) un **flow invité native Claudy** qui remplace progressivement le formulaire Tally actuel — deux variantes pour deux publics : **`/reservation` (B2C)** pour familles/amis (composition libre, vérification temps-réel de la disponibilité dès le choix des dates, paiement Stripe direct) et **`/sejour-entreprise` (B2B)** pour mises au vert et team buildings (sélection d'un pack prédéfini, ajout d'options, devis avec TVA + assistance dédiée). L'invité peut consulter sa réservation/payer via lien token, sans création de compte Devise, (3) une **API JSON** sous `namespace :api { :v1 }` pour les agents IA — Bearer-authentifiée (`AGENT_API_TOKEN`), supporte **lecture ET écriture authentifiée** (GET, PATCH pour mises à jour partielles, DELETE pour soft-delete) ; toutes les mutations sont tracées PaperTrail et soumises à P2 (jamais de hard-delete sur les modèles auditables), (4) une notion de **séjour-composite** qui agrège dans un même panier client : hébergement + activités + options de salle + buffet + pain (tranches-de-vie) + événements, payable en un seul Stripe Checkout, (5) un **tableau de bord par Pôle** où chaque pôle voit son budget annuel, ses recettes, ses dépenses, ses projets, tâches, membres, réunions et décisions — et où les données enregistrées dans Claudy nourrissent Winbooks (comptabilité fondation) sans le remplacer, (6) une **app mobile client** pour les invités en séjour : scan d'achats au bar/épicerie, choix/réservation d'activités en cours de séjour, consultation du séjour-composite en temps réel, paiement final, (7) un **reporting transversal** qui agrège l'activité économique de tous les domaines (hébergements + salles + activités + événements + bar + épicerie + boulangerie) en chiffre d'affaires, fréquentation/occupation, volumes vendus et tendances — distinct de BudgetTracking par-pôle (surface 5) car aggrégé par domaine, pas par centre de coût, (8) une **API publique sans auth** consommée par le site web (`les4sources.be`) pour afficher en temps réel les événements, activités, gîtes/salles disponibles et leur catalogue — distincte de l'API agent IA `:v1` (qui est Bearer-protected pour Bee + futurs agents internes). V1 livrée aujourd'hui couvre les surfaces 1, 2, 3, une partie de la 4 (hébergement + paiement Stripe natifs), un reporting partiel pour héb/salles seulement via `accounting_controller` ; les surfaces 4-complète, 5, 6, 7-globalisé et 8 restent à construire.

## Criteria

- [ ] ISC-1: `bin/dev` boote Rails + Vite et la page calendrier (root route `pages#calendar`) rend sans erreur dans un navigateur sur `localhost:3000`.
- [ ] ISC-2: Un invité avec un lien-token complet le flow `public` jusqu'au paiement Stripe et obtient une confirmation par email Postmark.
- [ ] ISC-3: Toute route hors `namespace :public` et hors `namespace :api` redirige vers `/users/sign_in` pour un utilisateur non authentifié Devise.
- [ ] ISC-4: Un webhook Stripe POST sur `/webhooks/stripe_hooks` persiste un `StripeEvent` et déclenche l'effet métier attendu (statut de paiement mis à jour).
- [ ] ISC-5: La page calendrier (`pages#calendar`) affiche bookings + space_bookings de l'utilisateur courant avec navigation mois/semaine fonctionnelle.
- [ ] ISC-6: `GET /api/v1` sans header `Authorization` → `401 unauthorized`. Avec `Authorization: Bearer $AGENT_API_TOKEN` valide → `200` + index JSON des ressources.
- [ ] ISC-7: `GET /api/v1/availability?from=2026-07-01&to=2026-07-07&lodging_id=N` retourne une disponibilité cohérente avec `Lodging#available_between?` (app/models/lodging.rb).
- [ ] ISC-8: Les enregistrements soft-deleted (`deleted_at IS NOT NULL`) sont absents de toutes les réponses API v1.
- [ ] ISC-9: Les réponses API n'exposent jamais `stripe_payment_intent_id` ni `stripe_checkout_session_id` (`grep -ri 'stripe_payment_intent_id\|stripe_checkout_session_id' app/views/api/v1/` retourne vide).
- [ ] ISC-10: La vue Organisation (`/organisation` ou équivalent) affiche un dashboard par cycle avec capacité, totaux d'heures, agenda items, et décisions.
- [ ] ISC-11: Un `git push` sur `main` déclenche un déploiement Hatchbox qui aboutit à un commit déployé visible sur `https://app.les4sources.be` sans intervention manuelle.
- [ ] ISC-12: Anti — `cat package.json | jq '.dependencies | keys'` ne contient ni `react`, ni `vue`, ni `@inertiajs/*` (Hotwire-only).
- [ ] ISC-13: Anti — `GET /api/v1/search` ou route équivalente de découverte publique → `404` (pas de marketplace).
- [ ] ISC-14: [TOMBSTONE — voir Changelog 2026-05-30. La conjecture "API v1 read-only" a été réfutée par la livraison du commit `07f88a6` qui ajoute PATCH + soft-delete pour les agents authentifiés.] Successeur : ISC-14.1 ci-dessous.
- [ ] ISC-14.1: Anti (remplace ISC-14) — toute écriture `PATCH`/`DELETE` sur `/api/v1/*` SANS Bearer `AGENT_API_TOKEN` valide retourne `401`. Avec token valide, l'écriture est tracée PaperTrail (version persisted with `whodunnit = "agent:<token-prefix>"` ou équivalent) et ne fait jamais de hard-delete sur les modèles couverts par soft_deletion. Probe : `curl -X PATCH /api/v1/customers/1` sans token → 401 ; avec token → 200 + entrée PaperTrail visible.
- [ ] ISC-15: Anti — aucune méthode `destroy` n'appelle `record.destroy!` sur les modèles couverts par `soft_deletion` ou PaperTrail (audit trail préservé).
- [ ] ISC-16: Anti (dérive P1) — tout modèle ActiveRecord métier exposable dans `app/models/` a un endpoint `/api/v1/<resource>` correspondant et une entrée dans `config/openapi/v1.yaml`. Probe : script d'audit qui liste les modèles métier et grep les routes + le YAML.
- [ ] ISC-17: Anti (dérive P2) — sur la liste auditable (bookings, payments, cycle_actions, decisions, humans, human_roles), aucun appel à `destroy!`/`delete_all` ne court-circuite soft_deletion ou PaperTrail. Probe : `grep -rn '\.destroy!\|delete_all' app/ | grep -iE 'booking|payment|cycle_action|decision|human|human_role'` retourne 0 hit non-tracé.
- [ ] ISC-18: Anti (dérive P3) — pas de namespace parallèle `app/<commerce>/` vs `app/<collective>/` ; pas de tables distinctes pour la même notion entre les deux mondes dans le schéma DB. Probe : `ls app/` et `psql -c '\dt'` audités semestriellement contre cette règle.

## Test Strategy

```yaml
- isc: ISC-1
  type: smoke-boot
  check: bin/dev boots, calendar route renders 200
  threshold: 200 OK
  tool: bin/dev + curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/

- isc: ISC-6
  type: api-auth
  check: 401 without token, 200 with valid token
  threshold: 401 / 200
  tool: |
    curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/v1
    curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $AGENT_API_TOKEN" http://localhost:3000/api/v1

- isc: ISC-7
  type: api-correctness
  check: availability matches Lodging#available_between?
  threshold: API and model agree on a random sample of 10 (lodging, date-range) pairs
  tool: rails runner spec/integration/availability_consistency.rb  # TODO: write

- isc: ISC-9
  type: api-leak-prevention
  check: stripe identifiers absent from jbuilder views
  threshold: 0 matches
  tool: grep -ri 'stripe_payment_intent_id\|stripe_checkout_session_id' app/views/api/v1/

- isc: ISC-12
  type: anti-stack
  check: no react/vue/inertia deps
  threshold: 0 matches
  tool: jq '.dependencies | keys | .[]' package.json | grep -E '^"(react|vue|@inertiajs)' || echo OK

# TODO: populate ISC-2, ISC-3, ISC-4, ISC-5, ISC-8, ISC-10, ISC-11, ISC-13, ISC-14, ISC-15 — the repo has
# no test suite yet (README "There are no tests for now"). Most probes will need to be either
# manual browser walkthroughs (Interceptor skill) or request specs written from scratch under spec/requests/.
```

## Features

```yaml
- name: BookingFlow
  description: |
    Flow invité token-based sous `namespace :public` — devis, réservation, Stripe Checkout, confirmation Postmark, webhooks Stripe persistés via StripeEvent.
    **Évolution majeure (horizon)** : deux **forms natifs Claudy** remplacent progressivement le formulaire Tally `3N4VpO` actuellement externalisé :
    - **`/reservation` (B2C)** — composition libre du séjour-composite : choix des dates avec **vérification temps-réel de la disponibilité** (gîtes physiques + composition Grand-Duc), choix d'activités au fil des sélections (calendrier de chaque activité pris en compte), affichage du panier qui se construit, paiement Stripe en fin de flow. Pas de "demande d'info → délai humain" — auto-réservation directe quand la dispo le permet. **Distinction info vs transaction préservée** dès l'entrée (analyse inbox : ~30% des inbound sont de l'info-seeking pur, à router différemment). **Catalogue Hulotte/Chevêche/Grand-Duc explicité dès la sélection** (1 thread sur 3 demande la différence aujourd'hui). **Champ animal/chien obligatoire** (politique 1/groupe + supplément à standardiser). **Tous prix affichés TVAC** avec mention "pas de TVA en plus".
    - **`/sejour-entreprise` (B2B)** — flow distinct optimisé team building / mise au vert : sélection d'un **pack prédéfini** parmi 3-5 packs ("Découverte ½ journée", "Cohésion 1 jour", "Off-Site 2 jours", "Off-Site Premium 3 jours"), choix de la date avec vérification dispo, ajustement des effectifs, ajout d'options, génération d'un **devis avec TVA explicite + facture + contact dédié**. Décision d'achat plus longue (2-6 semaines), parfois multi-étape, parfois sans paiement immédiat.
    Les deux forms partagent le moteur de disponibilité + le moteur de pricing (cf. Feature `PricingModel`) — ils diffèrent par UX et catalogue exposé.
  satisfies: [ISC-2, ISC-4]
  depends_on: [StayComposite, PricingModel, PublicApi]
  parallelizable: false

- name: Calendar
  description: Root UI (pages#calendar) — simple_calendar gem with custom overrides in app/calendars/simple_calendar/. Shows bookings + space_bookings, month/week navigation.
  satisfies: [ISC-1, ISC-5]
  depends_on: [Authentication]
  parallelizable: false

- name: Catalogue
  description: Lodgings, rooms, spaces — relatively static reference data, seeded via rails db:seed. Includes Lodging#available_between?/available_on? and Space#available_on?.
  satisfies: [ISC-7]
  depends_on: []
  parallelizable: true

- name: Organisation
  description: Per-cycle workload dashboard — cycles, cycle_actions (archived + active), gatherings, agenda_items, decisions, humans, roles, human_roles. Recent commits focus heavily here.
  satisfies: [ISC-10]
  depends_on: [Authentication]
  parallelizable: true

- name: ApiV1
  description: |
    JSON API under namespace :api { :v1 } — Bearer token auth via AGENT_API_TOKEN, jbuilder serialization, OpenAPI spec at /api/v1/openapi.json, excludes soft-deleted and Stripe identifiers.
    **Initial scope** (2026-05-28) : read-only, built per Plans/l-app-est-actuellement-accessible-woolly-cocoa.md, merged in commit e832bd6.
    **Évolution 2026-05-30 (tranche 1 deliverable)** : commit `07f88a6` ajoute **PATCH (partial update) + DELETE (soft-delete) sur tous les modèles couverts** pour les agents authentifiés. Mutations tracées PaperTrail. Pas de hard-delete sur modèles auditables (P2). Pas de POST de création pour l'instant — la création vient avec les futurs flows (BookingFlow B2C natif, kiosk, GuestMobileApp).
  satisfies: [ISC-6, ISC-7, ISC-8, ISC-9, ISC-13, ISC-14.1]
  depends_on: [Catalogue, BookingFlow]
  parallelizable: true

- name: Authentication
  description: Devise + role models (Role, HumanRole) — no Pundit/CanCan, authorization lives in controller before_actions. Public namespace bypasses Devise via token.
  satisfies: [ISC-3]
  depends_on: []
  parallelizable: false

- name: Deployment
  description: Hatchbox → Linode VPS, automatic on push to main. No staging.
  satisfies: [ISC-11]
  depends_on: []
  parallelizable: true

- name: AuditTrail
  description: soft_deletion + PaperTrail across audited models. No destroy! on models with audit coverage.
  satisfies: [ISC-15, ISC-17]
  depends_on: []
  parallelizable: true

- name: PolesAndServices
  description: |
    Structure à deux niveaux (cf. P6) :
    - **4 Pôles économiques** : Accueil (Malau), Artisanat (Seb+Olivier), Micro-ferme (Magali+Michael), Formations et animations socio-culturelles (Gaelle).
    - **4 Services support** : Administratif et financier, Communication, Gouvernance, Technique.
    Modèle `Team` existant (`app/models/team.rb` + breadcrumb "Pôles" dans `teams_controller.rb`) avec `bundles` et `tasks`. À enrichir : typage pôle-éco vs service-support, pilote(s), membres actifs, projets affiliés, réunions du pôle, décisions du pôle.
  satisfies: []
  depends_on: []
  parallelizable: true

- name: ScopedExternalAccess
  description: |
    Accès Claudy scopé pour les freelances qui interviennent dans certains Services support (ex. Emilie en Communication, Manon en Administratif). Aujourd'hui Devise + Role/HumanRole gère les utilisateurs internes ; ce bloc étend l'autorisation pour permettre à un compte externe de voir/agir uniquement sur le périmètre d'un Service donné (par ex. les humans/contacts mais pas les paiements), sans donner accès à l'ensemble de l'app.
  satisfies: []
  depends_on: [PolesAndServices]
  parallelizable: true
  status: horizon

# === Horizon / partial features (not yet ISC-covered) ===

- name: StayComposite
  description: |
    Notion de panier-séjour qui agrège hébergement + activités + options de salle + buffet + pain + événements en un seul checkout Stripe. Pivot architectural majeur — probablement un nouveau modèle `Stay` (ou refonte de `Booking`) qui devient le head d'un graphe d'items réservables.
    **Spec customer-facing canonique** = formulaire Tally `3N4VpO` à `https://formulaires.les4sources.be/sejour` (10 écrans, 33 questions, 9 branches conditionnelles). Le form matérialise déjà la composition réelle d'un séjour : **2 gîtes physiques + 1 composition** — *La Hulotte* (15p) et *La Chevêche* (8p) sont deux unités distinctes ; *Le Grand-Duc* (25p annoncé) est la **composition** des deux, sa réservation bloque les deux sous-unités ; plus camping (tentes, hamacs, van/camping-car) + salles (Grande Salle, Petite Salle) avec options modulaires + 10 activités à pricing variés + repas (Pizza Party, végé, buffet) + pre-order épicerie/boulangerie + cuisine pro.
    **Pricing à supporter** : per-personne, à l'heure, forfait groupe, base + per-pers, et pre-order (lead time devenu flexible avec la nouvelle app Tranches de Vie). Le modèle de prix doit être un polymorphisme propre — pas un champ unique.
    **Réf détaillée** : memory `reference_les4sources_tally_form.md`.
    **État de build (2026-07-15)** — n'est plus `horizon` : le modèle `Stay` est **livré en prod** (tranche 1, 2026-05-30 : Customers + StayComposite + LegacyBookingMigration). En cours : **epic #26 « Payment devient Stay-first »**, 4 phases (une PR par phase) :
      - Phase 1 — Stay public (token) + `payment_status` porté par Stay — **PR #42 mergée (13/07)**.
      - Phase 2 — flux Stripe Stay-first (redirections success/cancel → `/sejour/:token`, webhook `checkout.session.completed`, `Reservations::Builder` avec/sans hébergement) — **PR #49 mergée (15/07)**.
      - Phase 3 — canal admin/OTA sur Stay (chaque Booking → Stay auto + Customer upserté par email, rake one-shot idempotente, Payment admin porte `stay_id`) — **PR #50 mergée + déployée (16/07)**.
      - Phase 4 — verrouillage (`payments:verify_stay_links` → 100 %, Payment sans `stay_id` invalide, `payments.booking_id` nullable en DB) — **PR #51 mergée + déployée (16/07)**.
    **Epic #26 CLÔTURÉ (16/07)** : 4 phases en prod, backfill exécuté (22 Stays créés, 29 Payment rattachés, `verify_stay_links` = 601/601 = 100 %). Trou d'auditabilité découvert et suivi hors périmètre : issue #52 (PaperTrail ne versionne pas les Payment — PK UUID vs `versions.item_id` bigint, viole P2).
    Clarification architecturale actée (epic #26) : **`Booking` ne disparaît pas — il devient l'objet d'occupation calendrier** (`lodging_id` + dates) et perd l'ancre de paiement + la page publique, qui remontent sur `Stay`.
  satisfies: []
  depends_on: [BookingFlow, Activities, Events, Bakery]
  parallelizable: false
  status: partial

- name: Activities
  description: Activités payantes portées par un membre du collectif (tarif horaire unique — règle P5) ou un prestataire externe (tarif négocié). Modèles déjà en place — `Experience` (price_cents + min/max_participants + duration) et `Service` (price_cents + human). Réservables dans le cadre d'un séjour OU en standalone. Manque l'intégration avec le booking flow et l'attachement à un Pôle.
  satisfies: []
  depends_on: [Poles]
  parallelizable: true
  status: partial

- name: Events
  description: Événements à date fixe — récurrents (ex. ateliers soudure mensuels, pizza parties du vendredi) ou one-shot (ex. théâtre Petit Chaperon Rouge). Modèle `Event` + `EventCategory` déjà en place avec `sales_amount_cents`, `attendees`, `status`. Remplace BilletWeb à terme. Manque réservation + paiement en ligne intégré au séjour-composite.
  satisfies: []
  depends_on: [Poles]
  parallelizable: true
  status: partial

- name: BarAndGrocery
  description: |
    Bar des 4 Sources (boissons, chips, accueille marcheur·euse·s et cyclistes — Pôle Accueil) et épicerie (œufs/jus-de-pomme micro-ferme + vrac + lait/chocolat/confiture/tisanes — Pôle Micro-ferme). Aujourd'hui hors Claudy : achats consignés dans un **carnet papier**, paiements virement/cash.
    Trois modalités d'achat à supporter dans l'ideal state :
    (a) **Kiosk sur place** — écran tactile au bar et à l'épicerie. Le kiosk épicerie est connecté à une **balance** (lecture du poids pour le vrac). Auto-service ou opéré par un membre du collectif présent.
    (b) **Scan mobile guest** — via la GuestMobileApp (QR code produit → ajout au compte de séjour).
    (c) **Carnet papier de backup** — toujours disponible quand internet est coupé (réalité aux 4 Sources). Le carnet reste la source de vérité de dernier recours ; la saisie ultérieure dans Claudy reconstitue la transaction.
    Toutes les modalités doivent dégrader proprement (queue locale + sync à la reconnexion OU fallback carnet) — aucune transaction silencieusement perdue. Recettes attribuées au pôle propriétaire.
  satisfies: []
  depends_on: [PolesAndServices, BudgetTracking]
  parallelizable: true
  status: horizon

- name: Bakery
  description: |
    Module boulangerie de Claudy — pain au levain cuit au feu de bois, productions des "bake days" (mardi + vendredi historiquement), gestion produits / variants / commandes / paiements / wallets / SMS+email clients.
    **Trajectoire** : aujourd'hui l'activité boulangerie vit dans une app web séparée (Tranches de Vie, https://tranchesdevie.les4sources.be) avec sa propre API REST (cf. memory `reference_tranchesdevie_api.md`, 16 ressources). L'ideal state est d'**absorber Tranches de Vie dans Claudy** — plus deux apps séparées, mais un module Claudy natif. Motivation principale : anti-silo (P7) — cross-sell épicerie ↔ boulangerie ↔ séjours, vente de produits épicerie aux clients boulangerie, et inversement.
    **Phase transitoire** : pendant la migration, Claudy peut consommer l'API Tranches de Vie en lecture (delegation pattern) — le sous-module agit comme un proxy enrichi. Le pre-order avec lead time strict de 7 jours **n'est plus une contrainte** (la nouvelle app TDV permet de commander longtemps à l'avance) — le délai métier reste mais devient flexible.
  satisfies: []
  depends_on: [StayComposite, BarAndGrocery]
  parallelizable: false
  status: horizon
  satisfies: []
  depends_on: [StayComposite]
  parallelizable: true
  status: horizon

- name: PricingModel
  description: |
    Moteur de pricing à **deux étages** qui sous-tend les deux forms de booking, le panier StayComposite, le devis B2B et le reporting.
    **Étage 1 — Backend (matrice de coûts + marge)** : chaque item réservable (gîte/composition, salle, option, activité, repas, pre-order) a un coût calculé via une matrice cohérente :
      `coût_total = coût_fixe (heures porteur × tarif horaire P5 collectif OU tarif négocié externe + matériel + part fixe lieu) + coût_variable_par_pers × n_pers`
    avec **tranches de groupe** (5-10p / 11-20p / 21-30p) qui peuvent réduire le coût par tête. Le **prix client** = `coût_total × marge`, avec marge B2C ~1.2-1.3× et marge B2B ~1.4-1.6× (incluant TVA, facture, assistance).
    **Étage 2 — Front (présentation au client)** :
    - B2C : composition libre, chaque item montre son prix à la sélection, panier qui se met à jour en temps réel.
    - B2B : **6 packs prédéfinis** dérivés du corpus inbox observé (cf. memory `reference_4sources_pole_accueil_analysis.md`) :
        1. **"Mise au vert" — équipe 15-25p** : Hulotte/Grand-Duc 2 nuits + salle + cuisine pro + 2 repas/jour + 1-2 activités → **1800-2800€ TVAC** (asbl, services publics, équipes)
        2. **"Team building demi-journée" — 25-40p** : repas midi + 2 ateliers parallèles + goûter apéro + bar → **1400-1800€ TVAC** (équipes proches, coopératives)
        3. **"Retraite scolaire" — 12-25 élèves** : Hulotte/Grand-Duc 2-3 nuits + grande salle + repas complets + 2-3 activités → **2000-3500€ TVAC** (rhéto, unschooling, mouvements jeunesse)
        4. **"Retraite bien-être animée externe" — 15-25p** : Hulotte/Grand-Duc 2 nuits + grande salle + repas végé + commande pain → **1800-2600€ TVAC** (animateur externe qui loue le lieu — *gisement sous-exploité*, modèle infra-as-a-service)
        5. **"Mariage tout-compris"** : tous espaces vendredi-dimanche + Grand-Duc + cuisine pro → **2600€/we** (à packager une variante "plein air sous tente" pour mariages >100p)
        6. **"Passants randonneurs/cyclos — journée"** : terrasse + bar + pizza party + commande pain → **150-400€** (activer Bienvenue Vélo)
    Le client choisit un pack, ajuste effectifs et date, voit éventuellement les options additionnelles. Pas de composition libre — un menu, pas un atelier-cuisine.
    **Matrice de prix actuelle déjà observée** (cf. analyse inbox section G) — c'est le seed déjà-existant :
    Hulotte 1n semaine 485€ / weekend ~745€/2n · Chevêche 1n 260-275€ / 3n 675€ · Grand-Duc 1n 600-750€ / 2n 1200-1350€ / 3n 1800-1950€ / semaine 2410€ · Tiny 70€/n · Camping tente 7,50€/pers/nuit · Van 15€/nuit · Grande salle 250-400€/jour · Petite salle 110-190€ · Cuisine pro 110-200€ · Repas végé midi 15€/pers · Buffet pain-fromages 12€/pers · Formule complète 35€/pers/jour · Goûter apéro 7€/pers · Pizza party 40€ allumage + 7€/pers patons · Activités 60-120€/h (porteur), zythologie 120€ + 7€/pers, disc-golf 120€ forfait 8p +15€/pers · Mariage 2600€/we. **Pas de TVA en plus, tout TVAC.**
    **Pré-requis (work item séparé)** : un **workshop d'audit des coûts** par activité, à mener avec les Pôles Artisanat + Formations et animations + Service Administratif et financier — la matrice ci-dessus encode déjà le prix de vente mais pas le coût de revient. Sans coûts au propre, on ne peut ni dégrader la marge de manière éclairée pour le B2C familial sensible au prix, ni packager pour des marges B2B saines. ~2-3h de travail collectif, matrice tenable pour 2-3 ans avec ajustement annuel.
    **Anti-pattern explicite** : ne pas afficher de prix dynamique en temps réel sur un flow B2B — c'est anxiogène pour un acheteur entreprise qui veut un prix simple et stable.
  satisfies: []
  depends_on: [PolesAndServices]
  parallelizable: false
  status: horizon

- name: BudgetTracking
  description: Tableau de bord financier par Pôle — budget annuel défini, dépenses et recettes enregistrées dans Claudy, comparaison "réalisé vs prévu" lisible par chaque pôle. Les données alimentent Winbooks (logiciel comptable de la fondation) en aval — Claudy n'est pas un logiciel comptable, c'est un système de gestion par centre de coût. Manque : modèle financier sur Team, schéma de catégorisation des dépenses, vue dashboard.
  satisfies: []
  depends_on: [PolesAndServices]
  parallelizable: true
  status: horizon

- name: Reporting
  description: |
    Tableau de bord **transversal** de l'activité économique du domaine — agrège tous les domaines opérationnels en un même endroit : hébergements + salles + activités + événements + bar + épicerie + boulangerie (tranches-de-vie).
    Métriques visées : chiffre d'affaires par domaine et global, occupation gîtes/salles (taux + nuitées + jours-salles), volumes vendus (boissons bar, vrac épicerie en kg, pains boulangerie), nombre d'événements + participants, recettes activités par porteur (membre collectif vs externe), évolution temporelle (mois/trimestre/année) et saisonnalité.
    État actuel : reporting partiel via `app/controllers/accounting_controller.rb` couvrant **uniquement hébergements + salles**. À étendre pour couvrir les autres domaines au fur et à mesure qu'ils sont intégrés à Claudy. Différent de BudgetTracking (par pôle, recettes vs dépenses vs budget) — Reporting est par-domaine et opérationnel, BudgetTracking est par-pôle et budgétaire ; les deux vues coexistent.
  satisfies: []
  depends_on: [StayComposite, Activities, Events, BarAndGrocery, Bakery]
  parallelizable: true
  status: partial

- name: PublicApi
  description: |
    API publique **sans authentification** consommée par le site web `les4sources.be` pour afficher en temps réel le catalogue : événements à venir, activités proposées avec pricing, disponibilité des gîtes et salles, etc. Distincte de l'`Api::V1` (Bearer-protected pour agents internes) et de la future `Api::Guest` (Bearer-token client en séjour pour écriture).
    Implications : namespace `:api { :public }` dédié, endpoints en lecture seule, agressivement cacheable (HTTP cache + Rails fragment cache), pas de PII, pas de données de gouvernance/finance internes — uniquement le catalogue commercial exposable. Le site `les4sources.be` consomme cette API plutôt que de maintenir un catalogue dupliqué — c'est ce qui maintient la cohérence "ce que dit le site = ce que vend Claudy".
  satisfies: []
  depends_on: [StayComposite, Activities, Events]
  parallelizable: true
  status: horizon

- name: Customers
  description: |
    Modèle ActiveRecord `Customer` — entité de premier ordre représentant un client (vs `Human` qui modélise les membres du collectif et leurs rôles internes). Cf. P8.
    **Clé unique** : `email` (citext, validation RFC, normalized lowercase). Un même email → un unique Customer même s'il revient via plusieurs canaux (Tally form, Airbnb, Booking.com, direct).
    **Attributs** :
    - `first_name`, `last_name`, `email` (unique), `phone` (E.164 normalisé)
    - `customer_type` enum : `individual` | `organization`
    - Si `organization` : `organization_name`, `vat_number` (optionnel), `peppol_id` (optionnel) — alimente le Goal surface 2 B2B
    - `address_*` (rue, code postal, ville, pays) — optionnel, requis pour facture
    - `language` enum : `fr` | `nl` | `en` (capturé via le canal d'entrée)
    - `stripe_customer_id` — réutilisable d'un séjour à l'autre
    - `notes` (rich text, Pôle Accueil interne) — préférences récurrentes, allergies, animaux, etc.
    - `marketing_consent`, `nps_eligible` — RGPD-conscious
    - `soft_deletion` + `PaperTrail` (P2)
    **Associations** :
    - `has_many :stays` (les séjours-composites, cf. `StayComposite`) → permet `Customer.stays.upcoming` et `Customer.stays.past`
    - `has_many :payments, through: :stays`
    - `belongs_to :human, optional: true` — si un client est aussi membre du collectif, link possible mais non requis
    **Surfaces exposées** :
    - **Client self-service** (via lien token email, pas de compte Devise) : voir tous mes séjours, télécharger factures, modifier coordonnées, gérer les préférences marketing.
    - **Pôle Accueil** : recherche par email/nom, vue d'ensemble historique client, notes internes.
    - **B2bCrm** : recurring customers, contracts, fidelity discount (dépend de cette Feature).
    - **API agent `Api::V1`** : `/api/v1/customers/:id` (lecture) — alimente Bee pour les questions du genre "quand X est-il revenu pour la dernière fois ?".
    Lié à P8.
  satisfies: []
  depends_on: [BookingFlow]
  parallelizable: true
  status: horizon

- name: LegacyBookingMigration
  description: |
    Migration one-shot des données existantes vers la structure cible : tous les `Booking` + `SpaceBooking` actuels deviennent des items d'un `Stay` (cf. `StayComposite`), et les emails extraits des bookings deviennent des `Customer` (cf. `Customers`), normalisés et dédupliqués par email lowercase.
    **Étapes** :
    1. **Audit pré-migration** : inventaire des Booking/SpaceBooking existants, comptage des emails uniques, identification des cas pourris (email manquant, doublons mal normalisés, casse différente, espaces).
    2. **Rake task migration** idempotent — peut tourner plusieurs fois sans dupliquer. Pour chaque Booking : (a) upsert Customer par email lowercase, (b) créer un Stay si pas déjà migré (marqueur `legacy_booking_id`), (c) attacher le Booking comme item du Stay, (d) idem SpaceBooking.
    3. **Préservation PaperTrail** (P2) : les versions existantes sur Booking/SpaceBooking doivent rester accessibles ; ne pas les supprimer. Le Stay-parent enregistre l'événement migration comme première version PaperTrail.
    4. **Rapport post-migration** : nombre de Stays créés, Customers créés (vs upsertés), bookings non migrés (avec raison), warnings (emails corrompus, doublons fusionnés).
    5. **Bascule** : période d'observation où les deux structures coexistent (anciens controllers Booking marchent toujours, nouveaux endpoints Stay marchent aussi), puis cutover quand confiance acquise.
    **Acceptance criteria** :
    - Tous les Stay créés sont retrouvables par leur Customer (par email).
    - Tous les bookings actifs (status confirmé, futurs ou passés < 12 mois) sont migrés.
    - Aucune perte de donnée historique (paiements, dates, montants, statuts).
    - Le calendrier de disponibilité avant et après est identique sur la même fenêtre.
    Feature transitoire — archivée une fois la bascule terminée.
  satisfies: []
  depends_on: [Customers, StayComposite]
  parallelizable: false
  status: horizon

- name: Faq
  description: |
    FAQ structurée alimentant à la fois le site web (via PublicApi), les forms natifs (`/reservation`, `/sejour-entreprise`) et la GuestMobileApp. Les 20 questions récurrentes identifiées par l'analyse inbox (cf. memory `reference_4sources_pole_accueil_analysis.md` section B) sont la base :
    1. Disponibilité aux dates 2. Combien ça coûte / devis 3. Hulotte vs Chevêche vs Grand-Duc 4. Détail des chambres 5. Procédure de réservation + acompte 6. TVAC ou TVA en plus 7. Politique chien 8. Politique annulation/remboursement 9. Quelles activités / programme 10. Cuisine équipée 11. Salle libre + horaire 12. Capacité salle/repas 13. Que faut-il apporter (draps/essuies/savons) 14. Check-in/check-out 15. Commande pain Tranches de Vie 16. Pizza party privée vs collective 17. Camembert party 18. Camping van/camping-car 19. Groupes scolaires/jeunesse 20. Numéro touristique Gîte Wallonie.
    À standardiser également : politique animal, BYO-trainer (yoga/animateur externe), spécificités végé/régimes/allergies, bagagerie check-out.
  satisfies: []
  depends_on: [PolesAndServices]
  parallelizable: true
  status: horizon

- name: B2bCrm
  description: |
    Module CRM B2B avec gestion de la **récurrence annuelle**. L'analyse inbox a documenté que ~60% des clients B2B sont récurrents (Communa, Empreintes/Ride to the Future, SPW, Croix-Rouge, Solidarcité, Coopiteasy, Funds for Good, etc.) — ils reviennent chaque année. Aujourd'hui, aucune mémoire client structurée. Fonctionnalités cibles : historique de séjour par client, contrats-cadres annuels, remise fidélité optionnelle, relance commerciale ciblée hors saison, génération automatique de devis "comme l'année dernière + X", export Peppol/facture pour les administrations publiques.
  satisfies: []
  depends_on: [PolesAndServices, PricingModel]
  parallelizable: true
  status: horizon

- name: AutoAcknowledgement
  description: |
    Accusé de réception **structuré** automatique sous **1 heure** pour toute demande entrante (form natif, OTA, mail direct). Contenu : confirmation date(s) libre(s) ou occupée(s) + fourchette de prix estimée selon les choix initiaux + lien vers FAQ/tarifs + estimation du délai de réponse humaine (24h-7j selon saison/complexité). Motivation : analyse inbox a documenté ~30% de threads démarrant par "c'est libre ?" + plusieurs cas d'abandon en haute saison sur délai trop long. **Sans remplacer le chaleureux Malau** — ce premier contact dégrossit, l'humain reprend pour les cas non-triviaux. Réduit la charge Pôle Accueil de ~50% sur les demandes simples (Tiny, Chevêche couple 1 nuit, bivouac).
  satisfies: []
  depends_on: [BookingFlow, PricingModel, Faq]
  parallelizable: true
  status: horizon

- name: PostStayNps
  description: |
    Mailing automatique J+7 post-checkout pour collecter feedback structuré côté **B2B + B2C-groupe** — l'analyse inbox a noté que la satisfaction est manifestement haute (5★ Airbnb, "magique", "magnifique") mais qu'il n'y a aucun NPS structuré côté Pôle Accueil hors OTA. Format léger : un score (0-10), une raison libre, et 2-3 axes spécifiques (accueil, repas, activités, lieu). Alimente le Reporting et permet de calibrer les packs B2B au fil du temps.
  satisfies: []
  depends_on: [BookingFlow]
  parallelizable: true
  status: horizon

- name: GuestMobileApp
  description: |
    App mobile pour les invités **pendant leur séjour** (PWA ou native — choix techno à arbitrer). Surfaces :
    (a) consultation du séjour-composite en temps réel (hébergement + activités réservées + options + pain + événements),
    (b) scan d'achats au **bar** et à l'**épicerie** (QR code produit → ajout au compte de séjour),
    (c) choix/réservation d'activités en cours de séjour (randonnée ânes, atelier soudure, etc.),
    (d) paiement final agrégé ou à chaque achat (à arbitrer).
    Auth probablement token-based (lien depuis email Postmark) — pas de création de compte Devise côté guest. Côté API : nécessite probablement un `namespace :api { :guest }` distinct du `:v1` (read-only agents) car le guest ÉCRIT (scan, réservation, paiement) — viole le principe read-only de v1. Côté staff l'app reste web-only (P4 + Out of Scope).
  satisfies: []
  depends_on: [StayComposite, BarAndGrocery, Activities]
  parallelizable: false
  status: horizon
```

## Decisions

- 2026-07-16 — **Epic #26 « Payment Stay-first » CLÔTURÉ et déployé en prod.** Les 4 phases sont dans `main` (release Hatchbox `f618701`). Finalisation menée en workflow multi-agents (Forge implémente, revue adversariale Claude sur la vérité terrain) : la phase 3 a été durcie (tous les canaux Booking — admin/OTA, funnel public, UpdateService — garantissent un Stay ; `payments_attributes` retiré des params), et la phase 4 a introduit deux vraies régressions attrapées par la revue puis corrigées (création paiement admin cassée par l'ordre assign-stay/valid? ; webhook Stripe qui n'encaissait plus). Backfill prod exécuté sous supervision Michael (SSH) : 22 Stays créés, 29 Payment rattachés, `verify_stay_links` = **601/601 (100 %)**, app vérifiée saine (agent-browser). **Leçon outillage** : combiner `schema` (forçage `StructuredOutput`) avec un agent Forge (codex) fait planter le workflow — codex n'appelle pas cet outil de façon fiable ; faire renvoyer du texte libre à Forge et laisser un agent Claude lire la vérité terrain. **Découverte hors périmètre → issue #52** : PaperTrail ne versionne aucun Payment (PK UUID vs `versions.item_id` bigint), viole P2.
- 2026-07-15 — **Epic #26 à mi-parcours + reclassement `StayComposite` en `partial`.** Phase 2 (flux Stripe Stay-first) mergée aujourd'hui via **PR #49** (conflit `db/schema.rb` résolu : version `2026_07_14_013705`, migrations `add_color_to_experiences` + `make_payments_booking_id_nullable` conservées). Bilan epic #26 : **phases 1-2 mergées, phases 3-4 restantes**. La Feature `StayComposite` passe de `horizon` à `partial` (le modèle `Stay` est en prod depuis la tranche 1) et intègre désormais le suivi des 4 phases. **Décision produit (Michael) : une fois l'epic #26 verrouillé, la prochaine priorité produit est l'intégration des activités (`Experience`/`Service`) dans le funnel / séjour-composite** — c'est là que le panier composite prend son sens (gîte + atelier + buffet en un checkout). Finalisation des phases 3-4 lancée en workflow multi-agents (une PR par phase, pas de merge auto — validation Michael avant déploiement Hatchbox).
- 2026-07-12 — **Epic #26 cadré : Payment devient Stay-first.** Décisions produit de Michael : (1) page publique Séjour dédiée `public/sejour/:token` (nouveau token général sur `stays`) pour les redirections Stripe et le self-service client ; (2) `payment_status` porté par `Stay` ; (3) périmètre élargi — **tout migre**, y compris le canal admin/OTA (chaque Booking obtient un Stay auto, chaque Payment un `stay_id`). Clarification architecturale : **Booking ne disparaît pas, il devient l'objet d'occupation calendrier** (lodging_id + dates) et perd l'ancre de paiement/la page publique. 4 phases, une PR par phase, `agent:ready` posé pour l'agent nocturne. Alimente directement la Feature `StayComposite`.
- 2026-07-12 — **Passe design mobile funnel B2C (epic #27, branche `design/reservation-funnel`)** : audit AC-D-01→09 + correctifs commités (`44f14aa`, `720eb61`, `eb3cd3f`). Root cause du débordement mobile identifiée dans le layout partagé `public_sheet` : l'item de la grille `justify-items-center` se dimensionnait au contenu intrinsèque (min-width 962px des tables calendrier) et gonflait le layout viewport mobile à 800px — fix `w-full min-w-0` sur la carte. `TailwindFormBuilder` supporte désormais `label: false` (les `form_with url:` sans modèle affichaient les noms bruts des champs). Zones de tap ≤44px étendues via `before:-inset` (vérifiées `elementFromPoint`). Gotcha dev : le JIT Tailwind sous Vite ne re-scanne pas les nouvelles variantes des vues Slim à chaud — redémarrer `bin/vite dev` après ajout de classes inédites. Restant : test de non-régression overflow (pas d'infra system-spec JS), validation tactile réelle, `min` dynamique du champ départ (AC-D-02).
- 2026-05-28 — **Seed-generated draft.** This ISA was bootstrapped via `Skill("ISA", "seed ~/code/claudy")` at tier E3 from: README.md, CLAUDE.md, package.json, Gemfile (inferred), `Plans/l-app-est-actuellement-accessible-woolly-cocoa.md`, last 30 git commits, `app/` directory structure. Principles / Verification / Changelog deliberately left empty per Seed workflow (author-driven). Next step: `Skill("ISA", "interview me on ~/code/claudy/ISA.md")` to refine Vision, author Principles, and audit Criteria.
- 2026-05-28 — **Stack correction during seed**: the invocation prompt described Claudy as "Rails + Inertia/React" but the actual stack is **Rails + Hotwire (Turbo + Stimulus) + Slim**. Recent commits (May 2026) explicitly migrate *away* from Flowbite JS to Stimulus controllers, reinforcing the Hotwire-only line. Inertia/React reference probably confused with Terranova (which IS Inertia/React). ISC-12 codifies the Hotwire-only constraint as a regression anti-criterion.
- 2026-05-28 — **API v1 status**: the read-only AI-agent API described in `Plans/l-app-est-actuellement-accessible-woolly-cocoa.md` is **merged** (commit `e832bd6` "Add private read-only API for AI agents"). Live at `https://app.les4sources.be/api/v1`. Bearer token in `AGENT_API_TOKEN` ENV var. Memory entry `reference_claudy_api.md` references it.
- 2026-05-28 — **No test suite yet** (README explicitly: "There are no tests for now"). Most ISC probes in Test Strategy are TODOs — they'll need either manual browser walkthroughs via the Interceptor skill or fresh request specs under `spec/requests/`. The empty test suite is the biggest fragility in this ISA's Verification story.
- 2026-05-28 — **ISA location**: written at `~/code/claudy/ISA.md` (project-root convention), not at `MEMORY/WORK/claudy/ISA.md` as the original invocation suggested. The Seed workflow specifies `<project_path>/ISA.md` for the long-lived project source of truth, matching Terranova's pattern (`~/code/terranova/ISA.md`).
- 2026-05-28 — **Principles P1-P4 authored via Interview**: P1 (dualité UI/agent, future-proof), P2 (rien ne se perd, tout se trace — PaperTrail + soft_deletion sur bookings/payments/cycle_actions/decisions/humans/human_roles), P3 (commerce et collectif partagent le substrat — Pôle Accueil mixe membres collectif + prestataires externes, frontière membrane), P4 (server-rendered par défaut, JS uniquement quand irremplaçable — confirmé par la sortie de Flowbite vers Stimulus en mai 2026). Anti-ISCs dérivés ajoutés (ISC-16, ISC-17, ISC-18).
- 2026-05-28 — **Vision refactor majeur après deep-dive Michael**. La Vision seed-générée traitait Claudy comme "hospitalité + collectif + API agent". Michael a fait remonter pendant l'Interview le vrai ideal state : Claudy est l'**outil de gestion quotidienne ET la mémoire opérationnelle** de la *totalité* de l'activité économique des 4 Sources — hospitalité (aujourd'hui), **activités** portées par membres (tarif horaire collectif unique) ou prestataires (tarif négocié), **événements** (remplaçant BilletWeb à terme), **bar/épicerie** (aujourd'hui virement/cash hors Claudy), **boulangerie** (via intégration de l'app tranches-de-vie). Le pivot conceptuel est la notion de **séjour-composite** — un client compose son séjour comme un panier (gîte + activités + buffet + pain + options + événements) payable en un seul Stripe Checkout. Vision, Out of Scope, Goal et Features mis à jour en conséquence. Les nouvelles features (StayComposite, Activities, Events, BarAndGrocery, Bakery) sont marquées `status: horizon` — pas d'ISC tant que le bloc n'est pas planifié.
- 2026-05-28 — refined: **Comptabilité — frontière Winbooks confirmée par Michael**. Claudy *facilite* la gestion comptable mais ne remplace pas le logiciel comptable de la fondation (**Winbooks**), qui reste l'outil légal pour factures fiscales / déclarations TVA / bilans. Claudy enregistre dépenses+recettes+paiements pour nourrir Winbooks en aval. Out of Scope reformulé en conséquence.
- 2026-05-28 — **P5 + P6 ajoutés**. P5 = rémunération horaire uniforme intra-collectif, libre extra-collectif (règle de gouvernance, pas paramètre commercial). P6 = gouvernance polynucléaire par Pôles — confirmé par la présence en code du modèle `Team` avec breadcrumb "Pôles" dans `teams_controller.rb`.
- 2026-05-28 — refined: **Activities + Events ne sont PAS pleinement horizon — ils sont *partial***. Lecture du code : `Event` + `EventCategory` existent avec `sales_amount_cents`/`attendees`/`status` ; `Experience` (avec price/min-max participants/duration) et `Service` (price + human) existent aussi. Ce qui manque, c'est l'intégration avec le booking flow / séjour-composite et le rattachement à un Pôle. Features marquées `status: partial` au lieu de `horizon`.
- 2026-05-28 — refined: **Pôle = Team en code**. `teams_controller.rb` breadcrumbe explicitement "Pôles". Le modèle `Team` existe avec `bundles` → `tasks`, mais aucun champ financier (budget, recettes, dépenses) — c'est le manque exact que Michael a remonté pendant l'Interview. Nouvelle feature `BudgetTracking` ajoutée, `status: horizon`, dépend de `Poles`.
- 2026-05-28 — **Site web parcouru** (`les4sources.be`) — confirme le catalogue (2 gîtes 25p, grand espace 30-100p, petit 10-30p, bivouac, cuisine pro), les types d'activités (soudure, low-tech, pizza, disc-golf, ânes/poneys, théâtre, écriture, teinture), les services (bar, boulangerie tranches-de-vie le vendredi), et les 3 projets embarqués (Semisto, De Branches en Planches, Tranches de Vie). Pas d'exposition publique de la structure en pôles — confirme que c'est une couche interne de gouvernance.
- 2026-05-28 — **P8 ajouté : "Le client est un objet de premier ordre"** + 2 nouvelles Features (`Customers`, `LegacyBookingMigration`). Le modèle de données actuel n'a pas de notion `Customer` — l'email du client est un champ libre sur chaque Booking, sans entité durable. Conséquence : impossible de fournir un client portal self-service, impossible pour le Pôle Accueil de voir l'historique d'un même client, impossible pour le B2bCrm de détecter la récurrence (qui est ~60% côté B2B selon l'analyse inbox). P8 érige `Customer` (email comme clé unique) en entité de premier ordre. Migration nécessaire : tous les Booking + SpaceBooking existants deviennent des items d'un Stay (cf. `StayComposite`), avec extraction des emails → upsert Customer. Feature `LegacyBookingMigration` ajoutée, `status: horizon`, transitoire (archivée après bascule). Acceptance critique : préservation PaperTrail + zéro perte de donnée historique + idempotence du script.
- 2026-05-28 — **Décision stack de livraison : Studio Super Génial (réponse C)**. Question soulevée par Michael : "Est-ce judicieux de créer un PRD ?". Le contexte est qu'aujourd'hui Claudy est codé par lui en grande partie. Décision : la team Studio Super Génial (agents `sg-cadreur` / `sg-directrice-artistique` / `sg-constructeur` / `sg-verificateur` / `sg-plume`) prendra en charge la livraison code. Conséquence directe : il faut produire un `docs/PRD.md` au format `sg-cadreur` qui devient le contrat de passation aval (consommé par sg-constructeur). L'ISA reste la source de vérité long-lived ; le PRD est une **vue dérivée scopée par release ou par feature** que sg-cadreur lit + augmente avec son framing (acceptance criteria atomique, questions de cadrage manquantes, public client, etc.). Prochaine étape : engager `sg-cadreur` pour produire le PRD initial à partir de l'ISA Claudy actuelle.
- 2026-05-28 — **Analyse approfondie de 12 mois de correspondance Pôle Accueil** (`les4sources.sejours@gmail.com`, ~200-250 threads/an, anonymisé). Rapport durable à `~/code/claudy/docs/research/2026-05-28-pole-accueil-inbox-analysis.md` (507 lignes), memory `reference_4sources_pole_accueil_analysis.md`. Plusieurs raffinements importants en découlent :
  - **PricingModel — 6 packs B2B concrets** dérivés du corpus réel (Mise au vert 15-25p / Team building demi-journée 25-40p / Retraite scolaire 12-25 / **Retraite bien-être animée externe** *gisement sous-exploité* / Mariage tout-compris / Passants randonneurs Bienvenue Vélo). Description Feature `PricingModel` enrichie avec brackets précis + matrice de prix observée chez Malau (Hulotte 485€, Grand-Duc 1n 600-750€, salles 110-400€, repas 12-35€/pers, activités 60-120€/h…). Cette matrice est le **seed déjà-existant** du moteur — il manque les coûts de revient pour piloter la marge proprement.
  - **BookingFlow `/reservation` (B2C)** enrichi : distinction info vs transaction dès l'entrée (~30% des inbound sont info-seeking pur), explicitation Hulotte/Chevêche/Grand-Duc (1 thread sur 3 confond), champ animal obligatoire, mention "TVAC, pas de TVA en plus" affichée.
  - **2 Constraints ajoutées** : (a) Claudy = source de vérité du planning, OTAs sont des clones aval (sync sortante uniquement) — analyse a documenté du double-booking réel ; (b) calendrier ouvert à +18 mois minimum (mariages 6-18 mois, mises au vert 3-9 mois, options pré-réservation 2-12 mois).
  - **4 nouvelles Features ajoutées** : `Faq` (20 questions récurrentes identifiées comme base), `B2bCrm` (récurrence annuelle ~60% des clients B2B, aujourd'hui sans mémoire structurée), `AutoAcknowledgement` (accusé de réception structuré sous 1h, réduit la charge Malau de ~50% sur les demandes simples), `PostStayNps` (NPS J+7 automatique).
  - **3 surprises notables intégrées discrètement** :
    - "Lieu" et "écolieu/tiers-lieu/vie collective" sont plus utilisés par les clients que "gîte" → vocabulaire à privilégier dans SEO, copy site, labels de form.
    - Le four à bois est mentionné dans ~25% des threads — *asset signature* à valoriser sur la page d'accueil.
    - Les clients qui abandonnent invoquent leurs *valeurs* qui ne correspondent pas au budget — c'est un compliment du positionnement, **ne pas baisser les prix** pour les capter ; offrir des entrées différenciées (camping, journée, "découverte").
- 2026-05-28 — **Migration Tally → 2 forms natifs Claudy + pricing doctrine intégré à l'ideal state**.
  - **Tally déprécié à terme.** Le formulaire `3N4VpO` sur `formulaires.les4sources.be/sejour` est un outil transitoire. L'ideal state vise deux forms **natifs Claudy** qui le remplacent : `/reservation` (B2C) et `/sejour-entreprise` (B2B). Cible UX critique : **vérification temps-réel de la disponibilité** dès la saisie des dates — auto-réservation directe pour les cas où la dispo est verte, plutôt que le pattern actuel "demande → délai humain → confirmation".
  - **B2C vs B2B sont deux funnels distincts**, pas un seul form avec branche conditionnelle. Différences fondamentales : public, comportement d'achat (immédiat vs cycle 2-6 semaines), exigence facture+TVA, présentation du catalogue (libre vs packs), affichage du prix (temps-réel vs prix de pack stable).
  - **Pricing doctrine adoptée dans l'ideal state** (cf. Feature `PricingModel`). Modèle à deux étages : backend = matrice `coût_fixe (heures × P5 ou externe + matériel + part lieu) + coût_var × n_pers` avec tranches de groupe et marges différenciées B2C (~1.2-1.3×) / B2B (~1.4-1.6×) ; front = composition libre côté B2C, packs prédéfinis (3-5) côté B2B. Pré-requis : **workshop d'audit des coûts par activité** avec Pôles Artisanat + Formations + Service Administratif et financier. La précédente "open question" sur le pricing est désormais une **décision actée** dans l'ideal state — restera à arbitrer les chiffres concrets (marges exactes, composition exacte des packs, tranches précises) au moment du build.
  - **Nouvelles dépendances Feature** : `BookingFlow` dépend désormais de `StayComposite`, `PricingModel` et `PublicApi`. `PricingModel` dépend de `PolesAndServices` (pour le tarif horaire P5 par défaut + tarifs négociés par les pôles concernés).
- 2026-05-28 — **5 corrections / extensions majeures après lecture du form Tally par Michael**.
  1. **Pre-order 7 jours boulangerie/épicerie obsolète** — la nouvelle app Tranches de Vie permet de commander longtemps à l'avance. Mémo `reference_les4sources_tally_form.md` et description Feature `Bakery` corrigés.
  2. **Le Grand-Duc = Hulotte + Chevêche** — il n'y a **pas 3 gîtes physiques** mais 2 unités (Hulotte 15p, Chevêche 8p) + 1 composition réservable (Grand-Duc 25p annoncé). Nouvelle Constraint ajoutée : `Lodging supporte la composition` — modèle `composed_of_lodgings` self-referential, réservation d'une composition bloque les sous-unités.
  3. **Nouvelle 8e surface du Goal : API publique** pour le site web `les4sources.be` — sans auth, lecture seule, expose le catalogue commercial (événements, activités, gîtes/salles, pricing). Distincte de `Api::V1` (agents internes Bearer) et future `Api::Guest` (clients en séjour Bearer pour écriture). Nouvelle Feature `PublicApi` ajoutée, `status: horizon`.
  4. **Tranches de Vie absorbée dans Claudy à terme** — l'app séparée disparaît, le module boulangerie devient natif Claudy. Motivation : anti-silo (P7), cross-sell épicerie↔boulangerie↔séjours. Feature `BakeryIntegration` renommée `Bakery` ; mémoire `reference_tranchesdevie_api.md` annotée avec la trajectoire stratégique. La delegation API actuelle reste valide en phase transitoire.
  5. **P7 ajouté : Anti-silo** — règle métier substrate-independent que les activités économiques se mixent. C'est ce principe qui justifie l'absorption de Tranches de Vie, la cross-sell sur GuestMobileApp, et le séjour-composite lui-même.
- 2026-05-28 — **Question ouverte : modèle de pricing pour les activités (notamment B2B mises au vert / team building)**. Michael cherche une approche qui facilite le pricing sans tomber dans la négociation cas-par-cas. Pistes proposées (à arbitrer en aval) :
  - Systématiser le modèle **base + per-pers** (déjà utilisé pour la zythologie 120€ + 7€/pers) à toutes les activités — couvre coûts fixes (porteur d'activité) + variable.
  - **Tarification par tranches** de groupe (5-10p / 11-20p / 21-30p), dégressive, plutôt qu'un prix unique.
  - **Packs prédéfinis** type "Pack Cohésion" (3 activités + repas + nuit), "Pack Découverte" (visite + repas + 1 activité) — réduit l'overhead décisionnel et facilite le pricing prédictible.
  - **Pricing matrice "type d'activité × taille de groupe"** — grille standardisée maintenue collectivement par les porteurs d'activités, plutôt que prix négocié individuellement.
  - **Tarif B2B distinct** (mises au vert/team building) — incluant explicitement TVA, facture, assistance dédiée, parfois +20-40% vs tarif B2C.
  - **Calculateur visuel** sur le form / l'UI — montre le prix total en temps réel pendant que le client compose, plutôt que tout en fin de flow (réduit l'anxiété acheteur entreprise).
  - **Préalable** : mettre les coûts par activité au propre (heures porteur × P5 tarif horaire collectif + matériel + part fixe lieu) — sans ça, le pricing reste de l'intuition. À discuter avec les pôles concernés (notamment Formations et animations socio-culturelles + Artisanat).
- 2026-05-28 — **Form Tally `3N4VpO` parcouru intégralement (10 écrans, 197 blocks)**. Le form est la **spec customer-facing canonique** du séjour-composite. Corrections + enrichissements :
  - **3 gîtes nommés** (et non 2 comme inféré du site) : *Le Grand-Duc* 25p, *La Hulotte* 15p, *La Chevêche* 8p. Catalogue d'hébergement enrichi avec bivouac (tentes), espace tente/hamac, espace van/camping-car, location de hamacs.
  - **10 activités** précises avec tarifs : tour découverte (120€ forfait), troupeau d'ânes (120€), grimpe arbres (60€/h), disc-golf (15€/pers), atelier acier de récup', atelier palettes, zythologie (120€ + 7€/pers), cuisine plantes sauvages saisonnier, identification champignons saisonnier, astronomie saisonnier.
  - **Salles** : Grande Salle + Petite Salle, avec options modulaires (sono, projection, installation, buffet pain-fromages+légumes de saison incluant boissons au Bar).
  - **Cuisine pro** monétisable séparément.
  - **Pre-order épicerie/boulangerie à 7 jours** — lead-time métier dur, capture critique pour StayComposite et Bakery.
  - **Pricing polymorphes** : per-personne, à l'heure, forfait, base+per-pers, pre-order. Le modèle Stay/Item doit supporter ce polymorphisme proprement.
  Description de la Feature `StayComposite` enrichie avec référence au form Tally et au memory `reference_les4sources_tally_form.md`. Description `Bakery` enrichie avec le lead time 7 jours.
- 2026-05-28 — **DÉCISION : strangler pattern, pas de rewrite v2**. Question soulevée par Michael : "faut-il créer une toute nouvelle app Rails v2 sur la base de l'ideal state?". Décision après analyse : **NON, on étend Claudy existant**. Raisons : (a) Claudy est en prod et porte des données réelles (bookings, paiements, PaperTrail, API agent live) — coût de migration trop élevé ; (b) l'ideal state est majoritairement de l'addition (Reporting, BudgetTracking, GuestMobileApp, Kiosk, ScopedExternalAccess, BarAndGrocery) — seul StayComposite est un vrai pivot du modèle, faisable en migration progressive ; (c) momentum actif sur le repo (commits réguliers mai 2026) ; (d) coût de l'ajout d'une suite de tests à l'existant < coût d'un rewrite complet ; (e) second-system effect (Brooks, Spolsky). Stratégie retenue : continuer à compléter l'ideal state dans l'ISA, puis dériver un roadmap depuis l'ISA, commencer par bâtir une suite de tests sur les modules critiques + attaquer la fondation StayComposite comme refactor progressif.
- 2026-05-28 — **Reporting transversal ajouté comme 7e surface du Goal**. Michael a précisé que le reporting actuel (`accounting_controller.rb`) couvre uniquement hébergements + salles ; l'ideal state vise un reporting globalisé sur les 7 domaines économiques (héb, salles, activités, événements, bar, épicerie, boulangerie). Nouvelle Feature `Reporting` créée, `status: partial` (parce que la base existe déjà). Distinction explicite avec BudgetTracking : Reporting est **par-domaine et opérationnel** (CA, occupation, volumes), BudgetTracking est **par-pôle et budgétaire** (recettes vs dépenses vs budget annuel). Les deux vues coexisteront.
- 2026-05-28 — **BarAndGrocery enrichi : kiosk + balance + carnet papier de backup**. Michael a précisé la modalité physique des ventes : aujourd'hui carnet papier exclusif ; dans l'ideal state un **kiosk à écran tactile** au bar et à l'épicerie (le kiosk épicerie connecté à une **balance** pour le vrac), plus le scan mobile via GuestMobileApp, plus le carnet papier qui reste en backup obligatoire (les coupures internet sont une réalité aux 4 Sources). Nouvelle Constraint ajoutée : **résilience offline** — aucune transaction sur place ne peut être silencieusement perdue à cause d'un réseau coupé. La description de la Feature BarAndGrocery a été enrichie en conséquence. Implication architecturale future : prévoir une **transaction queue locale** côté kiosk (probablement SQLite/IndexedDB + sync à la reconnexion) — le pattern PWA serait cohérent avec ce besoin et avec P4.
- 2026-05-28 — **GuestMobileApp ajoutée comme 6e surface du Goal**. Michael a dévoilé que l'ideal state inclut une app mobile *côté client en séjour* (scan d'achats bar/épicerie, choix d'activités en cours de séjour, consultation du séjour-composite). Cela contredit l'Out of Scope original "pas d'app mobile native" — corrigé pour distinguer **staff** (web-only, OK) de **guest** (app mobile dans l'ideal state, techno PWA vs native à arbitrer). Implication architecturale notable : l'app guest écrit (scan = create purchase, réservation activité = create booking item), ce qui ne tient pas dans le `:api { :v1 }` actuel read-only — probablement besoin d'un nouveau `namespace :api { :guest }` avec auth token et règles d'écriture limitées. Nouvelle Feature horizon `GuestMobileApp` (dépend de StayComposite, BarAndGrocery, Activities). Le nom de la feature est volontairement anglais (`GuestMobileApp`) conformément à la règle qu'on vient d'établir.
- 2026-05-28 — **Convention de nommage rappelée par Michael — identifiants code TOUJOURS en anglais**. Le repo Claudy suit cette convention (Team, Booking, Lodging, Human, Cycle, Decision, Event, Experience, Service…). Trois Features avaient été nommées en français dans l'Interview précédent et ont été renommées : `SejourComposite` → `StayComposite`, `BarEpicerie` → `BarAndGrocery`, `BoulangerieIntegration` → `Bakery`. Le modèle proposé `Sejour` devient `Stay`. La prose et le vocabulaire métier (séjour, pôle, boulangerie, épicerie) restent français — c'est uniquement les identifiants code qui basculent. Memory `feedback_code_identifiers_english_only.md` créée.
- 2026-05-30 — **Tranche 1 livrée en production** (Customers + StayComposite + LegacyBookingMigration). 15 commits, première vraie suite de tests du repo (model + service + request specs), MergeService de fusion de doublons (cf. décision Michael 2026-05-28), migration legacy idempotente avec rapport ventilé, badge plateforme Airbnb/Booking.com sur Stay, et **bonus non-prévu** : workflow humain-in-the-loop de **re-ventilation interactive** (modale de réassignation + outils de matching email supervisé, commits `bc1b02d`/`ddb064f`/`a383718`/`55c2177`/`3267875`) pour les cas où la dédup automatique ne capte pas le bon Customer. Aussi : perf calendrier (N+1 éliminé) + tracing Sentry activé. Verification + Changelog à compléter dans une passe ultérieure.
- 2026-05-30 — refined: **API `:v1` n'est plus read-only — bascule en lecture+écriture authentifiée**. Commit `07f88a6` ("API agent : édition (PATCH) et suppression (soft-delete) sur tous les modèles") étend l'API agent v1 au write authentifié : `PATCH /api/v1/<resource>/:id` pour mises à jour partielles, `DELETE /api/v1/<resource>/:id` pour soft-delete. Toutes les mutations sont tracées PaperTrail. Pas de `POST` de création pour l'instant — la création est différée aux futurs flows (BookingFlow B2C natif, kiosk, GuestMobileApp). Conséquences ISA : (a) Goal surface 3 réécrite (n'est plus "read-only") ; (b) Feature `ApiV1` description mise à jour ; (c) **ISC-14 (anti-criterion "API write returns 404/405") tombstoned**, remplacé par **ISC-14.1** qui codifie la nouvelle posture (write authentifié obligatoire + PaperTrail + pas de hard-delete) ; (d) la future Feature `ScopedExternalAccess` reste pertinente pour les freelances externes (les agents internes restent eux dans `:v1` avec le `AGENT_API_TOKEN` partagé) ; (e) la future `Api::Guest` pour clients en séjour reste un namespace distinct (auth token client, pas `AGENT_API_TOKEN`). Entrée Changelog C/R/L correspondante à ajouter ci-dessous.
- 2026-05-28 — **Liste complète des Pôles + Services support obtenue de Michael**. Structure à deux niveaux fixée :
  - **4 pôles économiques (génèrent des recettes)** : Accueil (hébergement/locations, Malau) · Artisanat (low-tech, bois et métal, Seb+Olivier) · Micro-ferme (poules, ânes, cochons, productions vivaces/arbres/arbustes, Magali+Michael) · Formations et animations socio-culturelles (événements/formations/ateliers, Gaelle).
  - **4 services support (transverses)** : Administratif et financier · Communication · Gouvernance · Technique.
  Certains services intègrent des **freelances externes** qui auront besoin d'accès scopé à Claudy (ex. Emilie/Communication, Manon/Administratif). P6 reformulé pour capturer cette dualité. Feature `Poles` renommée `PolesAndServices`. Nouvelle feature horizon `ScopedExternalAccess`. Le modèle `Team` actuel n'a pas encore le typage pôle-éco vs service-support — c'est un raffinement à venir.

## Principles

- **P1 — Future-proof par dualité d'accès.** Tout objet métier dans Claudy doit être interrogeable à la fois par l'UI humaine et par l'API agent. L'API n'est pas une feature ajoutée — c'est une surface de premier ordre, au même rang que la vue humaine. Conséquence opérationnelle : chaque nouveau modèle introduit doit prévoir son endpoint `/api/v1/<resource>` et son entrée OpenAPI ; aucune logique métier ne reste piégée dans une view. C'est ce qui garde Claudy ouvert à Bee aujourd'hui et aux agents internes de demain sans rouvrir l'architecture.

- **P2 — Rien ne se perd, tout se trace.** Tout changement d'état sur un objet métier auditable de Claudy est réversible ou tracé. Pour une série d'objets cœur (à minima : bookings, payments, cycle_actions, decisions, humans, human_roles), une trace historique des updates est obligatoire — *qui* a modifié, *quand*, et *quel champ* a changé. C'est cohérent avec la stratégie « ancrer les projets dans la durée » (S3 TELOS) et avec la réalité d'un domaine piloté par un collectif où les gens vont et viennent : un nouvel arrivant doit pouvoir remonter le fil d'une réservation ou d'une décision des années plus tard sans rien deviner. Substrat technique : PaperTrail pour le `qui/quand/quoi`, `soft_deletion` pour la non-destruction.

- **P3 — Commerce et collectif partagent le même substrat.** Un booking de gîte payant et une cycle-action d'un membre du collectif vivent dans le même schéma, sont visibles dans le même calendrier, et sont gérés par les mêmes patterns (decorators, services, components, jbuilder partials). Pas de fork architectural entre les deux mondes — Claudy est un seul système qui sert les deux rythmes du domaine. C'est aussi cohérent avec la réalité humaine : les réservations sont gérées par le **Pôle Accueil**, qui mélange membres du collectif et prestataires externes (nettoyage, etc.) ; la frontière commerce/collectif n'est pas un mur, c'est une membrane perméable que Claudy doit refléter. Conséquence : la tentation future de séparer un "back-office hospitalité" d'un "back-office collectif" en deux apps est explicitement fermée.

- **P4 — Server-rendered par défaut, JS uniquement quand irremplaçable.** Si Rails + Slim + Turbo peuvent rendre l'interaction côté serveur, on les laisse faire. Quand le client a vraiment besoin d'interactivité, on l'isole dans un contrôleur Stimulus écrit à la main — pas dans un framework JS, pas dans une lib externe qui ajoute son runtime. Le but n'est pas l'élégance : c'est la **durabilité**. Une dépendance JS de 2026 sera cassée en 2030 ; un contrôleur Stimulus de 50 lignes restera lisible. Claudy étant maintenu quasi-solo, on n'a pas l'énergie pour suivre les refactos de l'écosystème frontend tous les 18 mois. Les commits de mai 2026 (sortie complète de Flowbite vers Stimulus) sont la matérialisation de ce principe.

- **P5 — Rémunération uniformisée à l'intérieur du collectif, négociée à l'extérieur.** Toute activité portée par un membre du collectif est rémunérée à un **tarif horaire unique**, identique pour tous les membres — c'est une règle de gouvernance, pas un paramètre commercial. Une activité portée par un prestataire externe peut avoir un tarif horaire différent, négocié au cas par cas. Cette règle exclut explicitement les schémas où certains membres seraient mieux payés que d'autres (séniorité, statut, etc.) et exclut la tentation d'introduire un tarif "porte-projet" intra-collectif. Conséquence pour Claudy : le calcul de rémunération d'une activité distingue toujours "membre collectif" (tarif unique) de "externe" (tarif libre), et le modèle de données doit refléter cette dualité.

- **P8 — Le client est un objet de premier ordre.** Toute interaction commerciale avec Claudy (réservation gîte, achat bar, scan épicerie, événement, formation, pré-commande boulangerie) attache un `Customer` identifié par son **email unique**. Conséquences : le client peut consulter en self-service tout son historique (séjours passés et futurs, paiements, factures, options réservées) ; le Pôle Accueil peut voir d'un coup d'œil toutes les interactions d'un même client ; le B2B CRM peut détecter la récurrence ; les analytics deviennent client-centriques. Cette règle exclut explicitement le pattern actuel où l'email du client n'est qu'un champ libre sur un Booking — il devient une clé unique vers une entité durable.

- **P7 — Anti-silo : les activités économiques se mixent.** Les différents domaines économiques des 4 Sources (hébergement, salles, activités, événements, bar, épicerie, boulangerie) ne doivent pas vivre en silos étanches. Le client de la boulangerie doit pouvoir voir et acheter à l'épicerie ; le client du gîte doit pouvoir réserver une activité ; le visiteur d'un événement doit pouvoir acheter au bar. Conséquences pour Claudy : (a) les domaines sont des Features distinctes du point de vue du code, mais leurs vues client et leurs catalogues s'interconnectent ; (b) le séjour-composite n'est qu'une matérialisation forte de ce principe pour le client en séjour ; (c) la décision d'absorber Tranches de Vie dans Claudy plutôt que de maintenir deux apps séparées découle directement de P7.

- **P6 — Gouvernance polynucléaire par Pôles + Services.** Les 4 Sources est organisé en **4 pôles économiques** (qui génèrent des recettes) et **4 services de support** (au service du projet et des pôles) : (a) **Pôles économiques** — Accueil (hébergement/locations, piloté Malau) · Artisanat (low-tech, bois et métal, piloté Seb+Olivier) · Micro-ferme (animaux + production alimentaire vivaces/arbres/arbustes, piloté Magali+Michael) · Formations et animations socio-culturelles (événements/formations/ateliers, piloté Gaelle). (b) **Services support** — Administratif et financier · Communication · Gouvernance · Technique. Chaque pôle a son périmètre semi-autonome (projets, tâches, membres, réunions, décisions, budget annuel) ; chaque service est transverse et peut être partiellement opéré par des **freelances externes** (ex. Emilie en Communication, Manon en Administratif) qui auront besoin d'accès scopé à Claudy. Cette structure à deux niveaux exclut explicitement le pattern "table unique de teams sans typage" — le modèle doit distinguer pôle économique (a une recette+dépense+budget) de service support (a un budget de dépenses + des intervenants potentiellement externes).
<!-- TODO author Verification once ISCs start landing. -->
## Changelog

- 2026-05-30 — Premier C/R/L de l'ISA Claudy (l'API v1 read-only) :
  - **conjectured** : l'API `:v1` reste read-only pour les agents IA, et toute écriture/mutation passe par l'UI humaine ou par un futur namespace `:api { :guest }` dédié aux écritures clients en séjour. (Posée à OBSERVE par le seed initial — ISC-14 anti-criterion : POST/PUT/PATCH/DELETE → 404/405.)
  - **refuted by** : la livraison de la tranche 1 (commit `07f88a6`, 2026-05-30) — l'écriture authentifiée (PATCH partiel + DELETE soft) sur tous les modèles `:v1` débloque des cas d'usage concrets côté agents internes (corriger un statut, soft-delete une décision obsolète, mettre à jour des notes Customer) qui auraient sinon nécessité une intervention humaine via l'UI Devise. La séparation lecture/écriture par namespace n'apportait pas de valeur — l'auth Bearer + PaperTrail + soft-deletion-only suffisent à garantir la posture P2.
  - **learned** : le bon axe de séparation n'est pas read vs write mais **qui** est l'agent (interne Bee/futurs vs guest en séjour). Les internes peuvent avoir un Bearer token largement scopé (lecture + write tracé) ; les guests auront un token court terme attaché à leur Stay, scopé aux écritures de leur propre panier seul (futur `Api::Guest`). La frontière est l'identité, pas le verbe HTTP.
  - **criterion now** : ISC-14.1 (anti écriture non-authentifiée + tracking PaperTrail obligatoire + pas de hard-delete sur modèles auditables) — remplace ISC-14 tombstoned.

