# BRIEF — Claudy, tranche 2 : `/reservation` B2C natif + PricingModel minimal

> Brief de passation au Cadreur (Studio Super Génial). Source de vérité long-lived : `~/code/claudy/ISA.md` — cette tranche **prolonge** la tranche 1 livrée le 2026-05-30 (Customer + Stay + LegacyBookingMigration) et remplace progressivement le formulaire Tally externalisé pour le canal B2C.
>
> Cette tranche 2 remplace l'ancien BRIEF tranche 1 (déplacé/archivé selon usage Studio SG — l'historique reste dans git).

---

## Projet

**Claudy** — app de gestion des 4 Sources (Yvoir, Belgique). Projet interne (cf. fiche `~/.claude/PAI/USER/PROJECTS/StudioSuperGenial/PROJETS-INTERNES.md`).

- **Repo** : https://github.com/les4sources/claudy
- **Chemin local** : `~/code/claudy`
- **ISA de référence (long-lived, source de vérité)** : `~/code/claudy/ISA.md` — *à lire avant de cadrer*. 7 Principles, 8 surfaces, ~15 Features.
- **Stratégie de livraison** : strangler pattern par tranches successives.
- **État au démarrage de cette tranche** : tranche 1 livrée en prod 2026-05-30. Customer + Stay + StayItem + migration legacy + admin Customer + MergeService + API v1 lecture+écriture authentifiée (PATCH/soft-delete).

## Stack frontend (verrouillée par l'ISA — non négociable)

**`Hotwire`** (Turbo + Stimulus + Slim, server-rendered). Verrouillée par P4 + ISC-12 de l'ISA. Pas d'Inertia, pas de React, pas de Vue.

## Scope de la tranche 2 — replacer Tally pour le canal B2C + poser le pricing minimal

### Pourquoi cette tranche, maintenant

L'analyse inbox 12 mois (cf. `~/code/claudy/docs/research/2026-05-28-pole-accueil-inbox-analysis.md`) a identifié que le formulaire Tally `3N4VpO` est le canal n°1 entrant (~70-90 demandes/an), mais qu'il génère 4 frictions structurelles documentées : (a) opacité de la disponibilité ("est-ce libre ?" dans 30% des threads), (b) opacité du tarif ("envoyez-moi un devis" quasi systématique), (c) confusion Hulotte/Chevêche/Grand-Duc (1 thread sur 3), (d) processus de réservation à 3 étapes mal raccordées (Tally → mail manuel Malau → app.les4sources.be). Chaque friction génère 3-5 allers-retours évitables et plusieurs abandons documentés.

Cette tranche supprime la quasi-totalité des frictions B2C — devis temps-réel, dispo temps-réel, lien stable.

### Deux features à livrer

1. **BookingFlow B2C natif** (`/reservation`) — un funnel public en remplacement de Tally pour les **familles, amis, anniversaires, weekends détente**. Cf. ISA Features → `BookingFlow`.
   - **Distinction info vs transaction** dès l'entrée — un sélecteur en page 1 ("je souhaite des infos" vs "je veux réserver"). Le path "info" peut continuer à passer par Tally pour cette tranche (Tally reste dispo pour B2B + info-seeking pur en parallèle).
   - **Sélection des dates avec vérification temps-réel de la disponibilité** — calendrier qui montre les jours libres/occupés pour Hulotte, Chevêche, Grand-Duc (composé) avant la sélection. Fenêtre calendrier ouverte à **+18 mois** (Constraint ISA — pour mariages et mises au vert annuelles).
   - **Catalogue hébergement clarifié** — chaque option avec nom, capacité, courte description, prix-soir indicatif. Le Grand-Duc explicitement marqué "= Hulotte + Chevêche réservées ensemble" pour fermer la confusion documentée.
   - **Composition libre du séjour** — ajout d'items au panier au fil des choix : hébergement, camping/bivouac (tente/hamac/van), salle(s) éventuelles, repas (Pizza Party, repas végé, buffet Petite Salle), pre-order épicerie/boulangerie. Activités et événements **hors-scope tranche 2** (intégrés en tranche ultérieure).
   - **Devis temps-réel** — le panier affiche le total prévisionnel **TVAC** au fur et à mesure (mention explicite "pas de TVA en plus", la confusion est documentée).
   - **Champ animal/chien** — obligatoire (politique 1/groupe + supplément à standardiser dans le PricingModel).
   - **Coordonnées client** — réutilise / crée un `Customer` (cf. tranche 1). Email = clé unique : si l'email existe déjà, le séjour est rattaché ; sinon création.
   - **Stripe Checkout** en fin de flow — paiement direct (pas le pattern actuel "lien automatique" qui frictionne). Acompte 50% par défaut, configurable.
   - **Lien token stable** envoyé par email (Postmark) pour consulter la réservation ultérieurement — pas de compte Devise côté guest.
   - **Auto-réservation directe quand la dispo est verte** — pas de "demande → délai humain → confirmation". Quand toutes les options sont disponibles et le paiement passe, le Stay est `confirmed`.

2. **PricingModel minimal** — moteur de calcul de prix scopé à la tranche 2. Cf. ISA Features → `PricingModel`.
   - **Pas le polymorphisme complet** de l'ISA (per-pers, à l'heure, forfait, base+per-pers, packs B2B) — uniquement les **structures observées chez Malau** dont la tranche 2 a besoin : forfait/nuit (Hulotte, Chevêche, Grand-Duc, Tiny si présent), forfait/jour ou demi-journée (Grande Salle, Petite Salle, Cuisine pro), €/pers/nuit (camping tente, hamac), forfait/nuit/véhicule (van), €/pers (repas 12-35€/pers selon type, buffet Petite Salle, pre-order épicerie), forfait+€/pers (Pizza Party 40€ allumage + 7€/pers patons).
   - **Tous prix TVAC** affichés tels quels — pas de TVA séparée à montrer au client.
   - **Forfait dégressif** où Malau le pratique aujourd'hui (3 nuits < 3×prix-1-nuit) — documenter le barème actuel et le coder dans le moteur. Pas de marges B2C/B2B différenciées (B2B = tranche ultérieure).
   - **Politique chien** standardisée : 1/groupe inclus + supplément X€/séjour (X à confirmer avec Michael au cadrage).
   - **Acompte 50%** par défaut sur le total — règle de base ; cas particuliers (pré-réservation, devis B2B) viennent en tranche ultérieure.
   - **Pas de packs prédéfinis** (ce sont les 6 packs B2B identifiés par l'analyse inbox — tranche ultérieure).
   - **Pas de tranches de groupe dégressives** (système 5-10p/11-20p/21-30p — tranche ultérieure).
   - **API** : `PricingModel.quote(stay_draft)` retourne un breakdown ligne par ligne TVAC, total, acompte. Le breakdown alimente à la fois l'UI temps-réel du form et le récap email post-réservation.

### Hors-scope explicite de la tranche 2 (anti-dérive)

- **Pas de form B2B** (`/sejour-entreprise`) — tranche 3 (avec packs B2B + devis TVA + facture).
- **Pas de packs B2B prédéfinis** — vivent dans PricingModel complet, tranche 3.
- **Pas de tarif horaire collectif P5** intégré au pricing — les activités ne sont pas dans le panier tranche 2.
- **Pas d'intégration Activities / Events** au panier — tranche ultérieure (les modèles `Experience`/`Service`/`Event` existent déjà, on les attachera à Stay plus tard).
- **Pas d'AutoAcknowledgement / Faq / B2bCrm / PostStayNps / PublicApi / GuestMobileApp / Kiosk / Reporting / BudgetTracking / BarAndGrocery / Bakery / ScopedExternalAccess** — toutes horizon, tranches dédiées.
- **Tally reste actif** pour le canal B2B + info-seeking pur durant la transition. Sa dépréciation côté B2C interviendra une fois que `/reservation` aura prouvé sa stabilité (mesure : 4-8 semaines de prod sans incident majeur).
- **Pas de migration Rails 8** — on reste Rails 7 + Ruby 3.1.2.
- **Pas de write API guest** (`Api::Guest`) — reste tranche ultérieure (GuestMobileApp / kiosk).
- **Pas de refonte de la booking flow `:public` actuelle** — coexistence durant la transition : l'ancien flow token-based reste actif pour les Stays existants ; `/reservation` est un nouveau funnel parallèle.

### Done pour la tranche 2 (haut niveau — sg-cadreur dérive les critères atomiques)

- `/reservation` accessible publiquement, full Hotwire, multi-étapes avec navigation Turbo
- Calendrier de dispo ouvert à +18 mois pour Hulotte, Chevêche, Grand-Duc (composé bloquant H+C)
- Composition de séjour testable end-to-end : choix dates → hébergement → camping/options → salle(s) → repas → pre-order pain → coordonnées → Stripe Checkout
- Devis TVAC mis à jour en temps réel à chaque modification du panier (sans rechargement complet — Turbo Frames)
- `Customer` upsert par email (réutilise tranche 1 logic)
- `Stay` créé en `confirmed` quand le paiement Stripe réussit ; en `pending` si paiement échoue ou est différé
- Lien token stable envoyé par Postmark à l'email du Customer pour consulter sa réservation
- Stripe webhook continue à fonctionner pour ce flow (réutilise infrastructure existante)
- Coexistence propre avec le `namespace :public` actuel — aucune régression sur les Stays créés via Tally avant la bascule
- `PricingModel.quote(stay_draft)` testé unitairement avec les barèmes documentés
- Vues admin Pôle Accueil — index des Stays récents avec filtrage par source (`/reservation` natif vs Tally legacy vs OTA) pour observer la transition
- Tests : model specs (PricingModel), service specs (booking flow service), request specs (`/reservation/*`), system spec d'au moins le happy-path B2C (sélection dates + composition + paiement Stripe en test mode)

## Pointeurs essentiels pour le Cadreur

- **ISA Claudy long-lived** : `~/code/claudy/ISA.md` — Features `BookingFlow` (section enrichie pour les deux variantes B2C/B2B, ne lire que la partie B2C pour cette tranche) et `PricingModel`. Principles P1, P2, P4, P8. Constraints (Lodging composé, calendrier +18m, OTA en aval de Claudy).
- **Tranche 1 livrée — pour rappel** : `Customer`, `Stay`, `StayItem`, `MergeService`, `LegacyBookingMigration::Runner`, `composed_of_lodgings` sur Lodging, API `:v1` read+write authentifiée.
- **Fiche projet** : `~/.claude/PAI/USER/PROJECTS/StudioSuperGenial/PROJETS-INTERNES.md` → Claudy.
- **Analyse customer voice (12 mois Pôle Accueil)** : `~/code/claudy/docs/research/2026-05-28-pole-accueil-inbox-analysis.md` — sections B (top 20 FAQ), D (frictions structurelles), G (matrice pricing observée), J (vocabulaire client). Très utile pour calibrer les labels du form et le copy.
- **Spec catalogue séjour (form Tally)** : memory `reference_les4sources_tally_form.md` — référence pour le catalogue à proposer (3 gîtes nommés, camping, salles, repas).
- **Code existant** : `Booking`, `SpaceBooking`, `Lodging` (avec `composed_of_lodgings` tranche 1), `Stay`, `StayItem` (tranche 1), `Customer` (tranche 1), `Payment`, `StripeEvent`, contrôleurs sous `namespace :public`. Décorateurs Draper, ViewComponent + Lookbook pour UI réutilisable.
- **Conventions repo** : Slim templates, Stimulus controllers pour interactions client, Tailwind, soft_deletion + PaperTrail.

## Questions de cadrage probablement nécessaires

Le Cadreur posera celles-ci à Michael (et toutes les autres qu'il jugera utiles) :

1. **Coexistence avec `namespace :public` actuel** — `/reservation` est un nouveau funnel, mais doit-on garder le pattern token-only `:public` pour les Stays créés via Tally legacy (en mode lecture / paiement de l'acompte) ? Ou on bascule progressivement tous les Stays sur le nouveau lien token de `/reservation` ?
2. **Politique chien — montant exact du supplément** : à standardiser dans PricingModel. Combien ?
3. **Barème de forfait dégressif** — la matrice observée chez Malau montre des dégressivités (Grand-Duc 1n=600-750€ / 2n=1200-1350€ / 3n=1800-1950€ / semaine=2410€). Formule fermée (ex: jour 1 = X, jour 2 = 0.9X, etc.) ou table de correspondance par durée ?
4. **Pre-order épicerie/boulangerie dans le flow** — le client commande dans `/reservation`, et Claudy passe la commande à Tranches de Vie via son API en arrière-plan ? Ou bien le flow `/reservation` propose juste un lien vers tranches-de-vie.les4sources.be en post-réservation (plus simple, moins intégré) ?
5. **Auto-réservation directe ou validation manuelle Malau ?** — pour les cas où la dispo est verte ET le paiement Stripe passe, est-ce qu'on confirme automatiquement (auto-réservation), ou est-ce que Malau reçoit un mail "demande confirmée à valider" et confirme manuellement comme aujourd'hui ? L'ISA pousse pour l'auto-réservation directe, mais c'est un changement de posture pour le Pôle Accueil — à confirmer.
6. **OTA double-booking** — la Constraint ISA dit "Claudy = source de vérité, OTAs en aval (sync sortante uniquement)". Mais aujourd'hui Airbnb/Booking peuvent injecter des bookings via leurs propres canaux. Est-ce que cette tranche 2 commence à bloquer côté Claudy les dates déjà occupées par un Stay natif, OU est-ce qu'on diffère ce sujet à une tranche dédiée "OTA sync" ?
7. **i18n** — l'analyse inbox observe un faible volume NL/EN mais Gîtes Wallonie pousse les exports. Est-ce que `/reservation` v2 est FR-only ou prévoit un selector langue dès cette tranche ?
8. **Politique d'annulation/remboursement** — l'analyse inbox note que c'est aujourd'hui au cas par cas. Cette tranche doit-elle standardiser une politique affichée dans le flow (ex: "annulation gratuite jusqu'à J-30, 50% jusqu'à J-7, non-remboursable après") ? Si oui, à arbitrer avec Michael avant le build.
9. **Source attribution** — comment marque-t-on le `Stay` créé via `/reservation` (vs Tally legacy vs OTA) pour le tableau de bord admin ? Probablement un champ `source` enum sur Stay. À ajouter à la tranche 1 ou à intégrer en tranche 2 ?

## Décisions Michael actées 2026-05-30 (avant cadrage)

- **Stack frontend** = Hotwire (verrouillé par P4 + ISC-12).
- **Tranche 2 = A** (BookingFlow B2C natif + PricingModel minimal, sans B2B, sans packs).
- **API v1 write** est désormais doctrine (acté dans l'ISA Changelog 2026-05-30 + ISC-14.1).

## Contraintes de livraison

- **Tranche déployable sur prod sans interruption** — coexistence avec `namespace :public` actuel et avec Tally form externalisé pendant la transition.
- **Pas de régression** sur les Stays créés via la tranche 1 ou via Tally legacy.
- **Tests** — la tranche 1 a posé les premiers vrais specs (model + service + request). Cette tranche les étend en ajoutant des system specs sur le happy-path B2C end-to-end (sélection → composition → paiement Stripe en mode test).

---
*Fin du brief. Le Cadreur produit `docs/PRD.md` validé par Michael avant tout build.*
