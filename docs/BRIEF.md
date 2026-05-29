# BRIEF — Claudy, tranche 1 : Customers + StayComposite + LegacyBookingMigration

> Brief de passation au Cadreur (Studio Super Génial). Source de vérité long-lived : `~/code/claudy/ISA.md` — cette première tranche **n'est qu'un sous-ensemble** de l'ideal state Claudy.

---

## Projet

**Claudy** — app de gestion des 4 Sources (Yvoir, Belgique). Projet interne (cf. fiche `~/.claude/PAI/USER/PROJECTS/StudioSuperGenial/PROJETS-INTERNES.md`).

- **Repo** : https://github.com/les4sources/claudy
- **Chemin local** : `~/code/claudy`
- **ISA de référence (long-lived, source de vérité)** : `~/code/claudy/ISA.md` — *à lire intégralement avant de cadrer*. Décrit l'ideal state complet (8 surfaces, ~15 features dont ~10 horizon).
- **Stratégie de livraison** : **strangler pattern** (décidée 2026-05-28 — pas de rewrite v2 from-scratch, on étend l'app existante par tranches).

## Stack frontend (verrouillée par l'ISA — non négociable)

**`Hotwire`** (Turbo + Stimulus + Slim, server-rendered). Verrouillée par le Principle P4 de l'ISA + ISC-12 (anti-criterion : aucun react/vue/@inertiajs dans `package.json`). Les commits récents migrent activement *loin* d'Inertia-like deps (sortie de Flowbite vers Stimulus pur).

## Scope de la tranche 1 — pivot architectural pur

Cette tranche ne change **aucun flow utilisateur visible**. Elle pose la **fondation du modèle de données** sur laquelle toutes les tranches suivantes (BookingFlow natif B2C, PricingModel polymorphe, packs B2B, AutoAcknowledgement, etc.) s'appuieront.

### Trois features à livrer

1. **Customers** — nouveau modèle ActiveRecord `Customer`, entité de premier ordre, clé unique `email` (citext, lowercase normalisé). Cf. ISA Features → `Customers`.
   - Attributs : `first_name`, `last_name`, `email` (unique), `phone` (E.164), `customer_type` enum (`individual` | `organization`), pour `organization` : `organization_name` + `vat_number` + `peppol_id` optionnels, `address_*`, `language` (`fr` | `nl` | `en`), `stripe_customer_id`, `notes` rich text Pôle Accueil, `marketing_consent`, `nps_eligible`.
   - Associations : `has_many :stays`, `has_many :payments, through: :stays`, `belongs_to :human, optional: true`.
   - `soft_deletion` + `PaperTrail` (cf. ISA Principle P2 + ISC-15/17).
   - Vues admin Pôle Accueil : index recherchable par email/nom, show avec historique, edit notes, **fusion de doublons** (sélectionner deux Customers détectés comme la même personne → merger toutes les associations sur le Customer cible + soft-delete du Customer source + entrée PaperTrail).

2. **StayComposite** — nouveau modèle `Stay` (tête d'un graphe d'items réservables). Cf. ISA Features → `StayComposite`.
   - Un `Stay` agrège des items réservables : `Booking` (hébergement), `SpaceBooking` (salle), futurs `ActivityBooking`, `EventBooking`, `MealOrder`, `BakeryOrder`, `BarCharge`, `GroceryCharge` (ces 6 derniers sont hors-scope tranche 1 — seuls Booking et SpaceBooking existent aujourd'hui).
   - Attributs : `customer_id` (FK), `arrival_date`, `departure_date`, `status` enum, `total_amount_cents`, `notes`.
   - Associations : `belongs_to :customer`, `has_many :stay_items` (polymorphique : booking, space_booking, …), `has_many :payments`.
   - `soft_deletion` + `PaperTrail`.
   - Lodging composé (Grand-Duc = Hulotte + Chevêche) : capturé via une Constraint d'ISA — réserver Grand-Duc bloque Hulotte + Chevêche. Mécanique à modéliser dans cette tranche (probablement via une self-referential `composed_of_lodgings` sur `Lodging`).

3. **LegacyBookingMigration** — script rake idempotent qui upsert `Customer` par email (lowercase) puis crée un `Stay` parent pour chaque ancien `Booking` / `SpaceBooking` orphelin, en préservant PaperTrail. Cf. ISA Features → `LegacyBookingMigration`. Feature transitoire (archivée après bascule).
   - Étapes : audit pré-migration (compter bookings, identifier emails pourris) → rake task `claudy:migrate:legacy_bookings_to_stays` → rapport post-migration (n_stays créés, n_customers créés vs upsertés, n_bookings non migrés + raisons).
   - Acceptance critique : zéro perte de donnée historique, idempotence prouvée (lancer 2× = même résultat), PaperTrail préservé.

### Hors-scope explicite de la tranche 1 (anti-dérive)

- **Pas de forms natifs Claudy** (`/reservation` B2C, `/sejour-entreprise` B2B) — tranche 2.
- **Pas de PricingModel polymorphe** — tranche ultérieure (déjà tracé en horizon dans l'ISA).
- **Pas de packs B2B prédéfinis** — découle du PricingModel.
- **Pas d'AutoAcknowledgement / Faq / B2bCrm / PostStayNps / PublicApi / GuestMobileApp / Kiosk / Reporting / BudgetTracking / BarAndGrocery / Bakery (TDV absorbée) / Activities / Events / ScopedExternalAccess** — toutes horizon, traitées dans des tranches dédiées une fois la fondation Customer + Stay en place.
- **Pas de refonte UI** — l'admin Pôle Accueil garde Hotwire/Slim existant, on étend juste les vues nécessaires aux nouveaux modèles.
- **Pas de migration vers Rails 8** — on reste Rails 7 + Ruby 3.1.2 (Constraint ISA).
- **Pas d'extension de l'API agent (`Api::V1`)** au-delà d'ajouter les nouveaux modèles en read-only — pas de write API pour cette tranche (l'écriture API guest est une tranche ultérieure).

### Done pour la tranche 1 (haut niveau — sg-cadreur dérive les critères atomiques)

- `Customer` model migré + créé avec validations + tests unitaires + indexation email unique
- `Stay` model migré + créé avec polymorphic stay_items + validations + tests
- `Lodging.composed_of_lodgings` self-referential + logique de blocage de dispo (réserver Grand-Duc bloque H+C)
- Migration script rake idempotent + dry-run + rapport
- API `/api/v1/customers/:id` et `/api/v1/stays/:id` exposés en read-only (jbuilder + OpenAPI yaml mis à jour)
- Vues admin Pôle Accueil pour Customer (index/show/edit) — en Hotwire/Slim
- Tous les Booking/SpaceBooking existants liés à un Stay + un Customer en prod après migration
- Zéro régression sur les flows existants (booking flow public namespace + paiement Stripe inchangés)
- PaperTrail préservé sur tous les modèles concernés
- Déploiement Hatchbox sur `main` réussit + db:migrate appliquée + post-migration check vert

## Pointeurs essentiels pour le Cadreur

- **ISA Claudy long-lived** : `~/code/claudy/ISA.md` (section Features → `Customers`, `StayComposite`, `LegacyBookingMigration` ; section Principles P1-P8 ; section Constraints).
- **Fiche projet** : `~/.claude/PAI/USER/PROJECTS/StudioSuperGenial/PROJETS-INTERNES.md` → Claudy.
- **Analyse customer voice (12 mois Pôle Accueil)** : `~/code/claudy/docs/research/2026-05-28-pole-accueil-inbox-analysis.md` — utile pour calibrer les attributs Customer (vocabulaire, language, customer_type observés, B2C vs B2B repartition).
- **Spec catalogue séjour (form Tally)** : memory `reference_les4sources_tally_form.md` — gîtes nommés (Hulotte 15p, Chevêche 8p, composition Grand-Duc 25p), confirme la mécanique Lodging composée.
- **Code existant** : modèles à étendre / référencer dans `~/code/claudy/app/models/` (Booking, SpaceBooking, Lodging, Room, Space, Human, Payment, Reservation, SpaceReservation, StripeEvent, …).
- **Conventions repo** : Slim templates, Draper decorators, ViewComponent + Lookbook, services par ressource, Devise + role models pour auth, jbuilder pour API.

## Questions de cadrage probablement nécessaires

Le Cadreur posera celles-ci à Michael (et toutes les autres qu'il jugera utiles) :

1. **Modèle Stay vs Booking** — `Stay` est un nouveau modèle distinct (Booking devient un `StayItem` polymorphe parmi d'autres) OU `Booking` est étendu pour devenir lui-même le Stay-parent ? La doctrine ISA pointe vers le premier (Stay = new model, Booking = item), mais c'est une décision de modélisation qui mérite confirmation.
2. **Bookings sans email** (anciens, OTA, manuel sans capture) — placeholder customer "anonyme" ? Skip avec rapport ? Demander à Malau de compléter manuellement ?
3. **Bookings via Airbnb/Booking.com** — l'email du guest passe-t-il par Claudy aujourd'hui, ou est-il masqué par l'OTA (`*@guest.booking.com`) ? Comment dédupliquer un même guest qui revient via deux canaux ?
4. **Lodging composé Grand-Duc** — la mécanique de blocage est-elle "Grand-Duc réservable seulement si H+C tous deux libres" (calculé) ou "Grand-Duc maintenu comme entité distincte, et on synchronise les calendriers via callback" ? Le calculé est plus simple mais demande une refonte des requêtes de dispo.
5. **PaperTrail sur la migration elle-même** — la création d'un Stay-parent autour d'un Booking existant doit-elle apparaître comme une "version" PaperTrail attribuée à un utilisateur système (par ex. `User.system` ou nil), pour que l'historique de l'ancien Booking reste cohérent ?
6. **Fenêtre de migration** — DÉCIDÉ : **tout** (passés + futurs + annulés + soft-deleted). Le rapport post-migration doit ventiler par catégorie (n_actifs / n_passés / n_annulés / n_soft-deleted / n_sans-email-skipped) pour traçabilité.
7. **Customer.notes** rich text — qui voit ces notes ? Pôle Accueil + collectif uniquement ? Ou aussi le client lui-même via son portail self-service (tranche future) ?
8. **Customer.language** — détecté automatiquement (depuis l'inbound channel, Accept-Language) ou demandé explicitement (au prochain contact) ?

## Décisions Michael actées 2026-05-28 (avant cadrage)

- **Hors-scope tranche 1 confirmé sans exception** — toutes les horizon features (BookingFlow B2C, PricingModel, packs B2B, FAQ, AutoAck, B2bCrm, PostStayNps, PublicApi, GuestMobileApp, Kiosk, Reporting, BudgetTracking, BarAndGrocery, Bakery, Activities, Events, ScopedExternalAccess) restent en dehors de cette tranche. Tranche 1 = pivot architectural pur (data model + migration).
- **Vues admin Customer** = minimal + **fusion de doublons** (cf. feature Customers ci-dessus).
- **Fenêtre de migration** = tout l'historique (cf. question 6 ci-dessus).

## Contraintes de livraison

- **Tranche déployable sur prod sans interruption** — Claudy est en prod active. Pas de fenêtre de maintenance prévue. Migration en arrière-plan + bascule progressive.
- **Coexistence durant la transition** — les anciens endpoints Booking continuent à fonctionner pendant que les nouveaux Stay/Customer s'installent.
- **Tests** — le repo n'a pas de suite de tests aujourd'hui. Cette tranche est une OPPORTUNITÉ de poser les premiers vrais request specs + model specs (sur les nouveaux modèles + la migration). Pas obligation de tester l'existant, mais tout le nouveau code DOIT être testé.

---
*Fin du brief. Le Cadreur produit `docs/PRD.md` validé par Michael avant tout build.*
