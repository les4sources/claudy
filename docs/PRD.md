# PRD — Claudy · Tranche 2 : `/reservation` B2C natif + PricingModel minimal

> Contrat de passation du studio Super Génial. Produit par le Cadreur depuis `docs/BRIEF.md` (tranche 2), dérivé de la source de vérité long-lived `~/code/claudy/ISA.md`. **À valider par Michael avant tout build.** Tous les agents aval lisent ce fichier. Vit dans le repo, versionné.

| Champ | Valeur |
|-------|--------|
| **Statut** | ✅ **VALIDÉ — prêt pour le Constructeur.** Michael a validé le PRD et tranché Q1-Q9 le 2026-05-30. Passage au Constructeur / Directrice Artistique / Vérificateur autorisé. |
| **Projet** | Claudy — app de gestion des 4 Sources (Yvoir, Belgique). Projet interne Studio Super Génial. |
| **Tranche** | 2 — prolonge la tranche 1 livrée en prod le 2026-05-30 (Customer + Stay + StayItem + LegacyBookingMigration + MergeService + API v1 read+write authentifiée). |
| **Stratégie** | Strangler pattern : funnel `/reservation` parallèle, coexistence avec Tally + `namespace :public` durant la transition. |
| **Repo** | https://github.com/les4sources/claudy · **Branche déploiement :** `main` · **Déploiement :** Hatchbox → Linode VPS (pas de staging) |
| **Stack** | Ruby on Rails 7.0 · Ruby 3.1.2 · PostgreSQL · Vite (`vite_rails`) · Tailwind · Devise · Stripe · Postmark · Sentry |
| **Stack frontend** | **`Hotwire`** (Turbo + Stimulus + Slim, server-rendered). Verrouillée par ISA P4 + ISC-12. **Pas d'InertiaJS, pas de React, pas de Vue.** *— ligne lue par Constructeur et Vérificateur, ne pas omettre.* |
| **Date** | 2026-05-30 (rédigé) · **2026-05-30 (validé — Q1-Q9 figées)** |

---

## 1. Problème & objectif

Le formulaire **Tally `3N4VpO`** est le canal entrant n°1 (~70-90 demandes/an) mais génère 4 frictions structurelles documentées (`docs/research/2026-05-28-pole-accueil-inbox-analysis.md`) : (a) opacité de la **disponibilité** (« est-ce libre ? » dans ~30 % des threads), (b) opacité du **tarif** (« envoyez-moi un devis » quasi systématique), (c) **confusion Hulotte/Chevêche/Grand-Duc** (1 thread sur 3), (d) **processus à 3 étapes mal raccordées** (Tally → mail manuel Malau → app.les4sources.be). Chaque friction = 3-5 allers-retours évitables + abandons documentés.

**Objectif tranche 2 :** livrer un funnel public natif `/reservation` (B2C) + un `PricingModel` minimal qui suppriment la quasi-totalité de ces frictions côté B2C — devis temps-réel, dispo temps-réel, lien stable, paiement direct — sans toucher au flow `:public` existant ni à Tally (qui restent actifs pendant la transition).

## 2. Utilisateurs / audience

- **Client B2C** (familles, amis, anniversaires, weekends détente) — public cible de `/reservation`. Pas de compte Devise : self-service par lien token email.
- **Pôle Accueil (Malau)** — utilisateur interne authentifié Devise ; observe la transition via une vue admin des Stays récents filtrable par source.
- **Hors-cible tranche 2 :** client B2B/entreprises (→ tranche 3, `/sejour-entreprise`) ; agents IA (API v1, livré tranche 1).

## 3. Périmètre (in-scope tranche 2)

### 3.1 Feature A — BookingFlow B2C natif (`/reservation`)

Funnel public Hotwire multi-étapes, navigation Turbo. Parcours :

1. **Entrée — distinction info vs transaction.** Sélecteur page 1 : « je souhaite des infos » (peut rester routé vers Tally cette tranche) vs « je veux réserver » (entre dans `/reservation`).
2. **Dates + dispo temps-réel.** Calendrier montrant jours libres/occupés pour Hulotte, Chevêche, Grand-Duc (composé). Fenêtre ouverte à **+18 mois** (Constraint ISA).
3. **Catalogue hébergement clarifié.** Nom, capacité, description courte, prix-soir indicatif. Grand-Duc marqué « = Hulotte + Chevêche réservées ensemble ».
4. **Composition libre du séjour** (panier au fil des choix) : hébergement, camping/bivouac (tente/hamac/van), salle(s), repas (Pizza Party, repas végé, buffet Petite Salle). **Pre-order épicerie/boulangerie = simple lien externe** vers `tranches-de-vie.les4sources.be` affiché en post-réservation (PAS d'intégration write API — Q4 tranchée B).
5. **Devis temps-réel TVAC** — panier mis à jour à chaque modif, sans rechargement complet (Turbo Frames), mention « pas de TVA en plus ».
6. **Champ animal/chien obligatoire** — supplément **50 € / chien / séjour** (Q2). Le supplément automatique du flow ne couvre **qu'UN seul chien** ; les séjours multi-chiens sont **hors flow**, traités manuellement par Malau.
7. **Coordonnées client** — upsert `Customer` par email (logique tranche 1).
8. **Stripe Checkout** — paiement direct, acompte 50 % par défaut (configurable).
9. **Lien token stable** envoyé par Postmark (pas de compte Devise guest).
10. **Confirmation Stay — validation manuelle par Malau (Q5 tranchée B, PAS d'auto-confirm).** `/reservation` + paiement Stripe crée une **demande / draft** (`Stay` `pending`) que Malau confirme manuellement ; le Stay ne passe **jamais** automatiquement en `confirmed`. Dispo verte + paiement OK ne déclenchent pas d'auto-réservation. *(Ceci écarte sciemment la posture auto-réservation de l'ISA — voir Journal de décisions + DRIFT-4.)*

### 3.2 Feature B — PricingModel minimal

Moteur scopé tranche 2, sous-ensemble du `PricingModel` complet de l'ISA. Structures de prix supportées (uniquement celles observées chez Malau, nécessaires au B2C) :

| Structure | Items |
|-----------|-------|
| forfait/nuit | Hulotte, Chevêche, Grand-Duc, Tiny (si présent) |
| forfait/jour ou ½-journée | Grande Salle, Petite Salle, Cuisine pro |
| €/pers/nuit | camping tente, hamac |
| forfait/nuit/véhicule | van |
| €/pers | repas (12-35 €/pers selon type), buffet Petite Salle, pre-order épicerie |
| forfait + €/pers | Pizza Party (40 € allumage + 7 €/pers patons) |

- **Tous prix TVAC**, affichés tels quels.
- **Moteur dégressif HYBRIDE (Q3 tranchée — hybride).** Deux mécanismes combinés, paramétrés **par hébergement** :
  1. **Formule fermée par défaut** : `prix = prix_nuit_1 + (n − 1) × prix_nuit_suivante`. Couvre automatiquement toute durée (4, 5, 6 nuits… sans table).
  2. **Forfaits nommés qui écrasent (override)** la formule pour certaines durées précises.
  - **Barème de référence Grand-Duc (à coder comme cas de test) :** `prix_nuit_1 = 750 €`, `prix_nuit_suivante = 600 €` ⇒ formule donne 1 350 € (2n), 1 950 € (3n), 2 550 € (4n)… **Forfait nommé « semaine » = 2 410 €** qui écrase la formule pour 7 nuits.
- **Politique chien standardisée (Q2 tranchée) : supplément 50 € / chien / séjour.** Le flow facture automatiquement **un seul chien** (50 €) ; multi-chiens = hors flow, traité manuellement par Malau (pas de calcul auto au-delà d'un chien).
- **Acompte 50 %** par défaut sur le total.
- **API** : `PricingModel.quote(stay_draft)` → breakdown ligne par ligne TVAC + total + acompte. Le breakdown alimente l'UI temps-réel **et** le récap email post-réservation (source unique).

### 3.3 Surfaces transverses

- **Vue admin Pôle Accueil** — index des Stays récents, filtrage par `Stay#source` (`reservation` vs `tally_legacy` vs `ota` vs `manual`) pour observer la transition. La colonne `source` est **ajoutée par migration T2** (Q9, voir §6).
- **Réutilisations tranche 1 :** infra Stripe + webhooks (`webhooks/stripe_hooks`, `StripeEvent`), upsert Customer par email, `composed_of_lodgings` sur `Lodging`.

## 4. Hors-périmètre (anti-dérive)

- ❌ Form B2B (`/sejour-entreprise`) — tranche 3.
- ❌ Packs B2B prédéfinis (les 6 packs ISA) — tranche 3.
- ❌ Tarif horaire collectif P5 dans le pricing — activités hors panier en T2.
- ❌ Intégration Activities / Events au panier (`Experience`/`Service`/`Event` existent, attachés à Stay plus tard).
- ❌ Tranches de groupe dégressives (5-10p / 11-20p / 21-30p) — tranche ultérieure.
- ❌ Marges B2C/B2B différenciées — B2B ultérieur.
- ❌ AutoAcknowledgement / Faq / B2bCrm / PostStayNps / PublicApi / GuestMobileApp / Kiosk / Reporting / BudgetTracking / BarAndGrocery / Bakery / ScopedExternalAccess — horizon, tranches dédiées.
- ❌ Write API guest (`Api::Guest`) — tranche ultérieure.
- ❌ Migration Rails 8 — on reste Rails 7 / Ruby 3.1.2.
- ❌ **i18n / sélecteur de langue (Q7) — FR-only en T2.** `/reservation` est en français uniquement ; pas de sélecteur FR/NL/EN cette tranche (le champ `Customer#language` existe mais n'est pas exposé dans le flow).
- ❌ **Politique d'annulation/remboursement affichée dans le flow (Q8) — NON en T2.** Aucune politique standardisée n'est affichée dans `/reservation` ; les annulations restent traitées au cas par cas, hors flow.
- ❌ **Blocage OTA double-booking (Q6) — NON en T2.** On ne bloque pas côté Claudy les dates prises par les OTAs ; le blocage de dispo ne joue qu'entre Stays natifs Claudy. La sync OTA reste une tranche dédiée ultérieure.
- ❌ **Pre-order épicerie/boulangerie intégré (write API TDV) — NON (Q4).** Le pre-order est un **simple lien externe** post-réservation, pas une commande passée à Tranches de Vie via API.
- ❌ Refonte de la booking flow `:public` actuelle — coexistence : ancien flow token-based actif pour les Stays existants ; `/reservation` est un funnel parallèle.
- ❌ Dépréciation de Tally côté B2C — reste actif pendant la transition (bascule visée : 4-8 semaines de prod sans incident majeur).

## 5. Pages & parcours (sitemap)

**Public (bypass Devise, comme `namespace :public`)**
- `GET /reservation` — étape 1 : sélecteur info vs transaction.
- `/reservation/*` — étapes Turbo : dates → hébergement → camping/options → salle(s) → repas → pre-order → coordonnées → Stripe Checkout.
- Retour Stripe (succès / échec) → confirmation ou reprise.
- Lien token stable (depuis email Postmark) → consultation read-only du Stay, sans Devise.

**Interne (Devise)**
- Vue admin Pôle Accueil — index Stays récents + filtre `source`.

**Inchangé (coexistence)**
- `namespace :public` actuel (Stays Tally legacy), `webhooks/stripe_hooks`, calendrier `pages#calendar`, `namespace :api { :v1 }`.

## 6. Modèle de données (pressenti, Rails)

> Le Constructeur confirme l'état réel des modèles tranche 1 à l'ouverture du code. Conventions imposées : décorateurs Draper, services par ressource (`app/services/<resource>/`), ViewComponent + Lookbook pour l'UI réutilisable, Slim, soft_deletion + PaperTrail sur tout modèle auditable.

- **`Stay`** (tranche 1) — head du séjour-composite. Champs touchés/attendus en T2 :
  - `status` (au moins `pending` / `confirmed` — `[HYPOTHÈSE]` à confirmer). **Note Q5 :** un Stay créé via `/reservation` reste `pending` jusqu'à validation manuelle Malau, même paiement réussi.
  - **`source` (string) — NOUVELLE COLONNE, ajoutée par MIGRATION T2 (Q9).** Le schema actuel (`db/schema.rb`) confirme que la table `stays` **n'a PAS** de colonne `source` aujourd'hui. Valeurs admises : `reservation` / `tally_legacy` / `ota` / `manual`. **Défaut = `reservation`** pour toute résa créée via `/reservation`.
  - ⚠️ **`source` est DISTINCT de `legacy_origin`.** `legacy_origin` existe déjà sur `stays` (clé d'import/dédup de la migration legacy, **index unique**) et ne doit **ni être confondu avec `source` ni réutilisé pour l'attribution de canal**. Le Constructeur crée bien une colonne `source` neuve.
  - token de consultation stable.
- **`StayItem`** (tranche 1) — items du panier (hébergement, camping, salle, repas, pre-order) avec prix-ligne TVAC.
- **`Customer`** (tranche 1) — upsert par email lowercase ; `has_many :stays`.
- **`Lodging`** (tranche 1) — `composed_of_lodgings` (Grand-Duc = Hulotte + Chevêche), `available_between?`.
- **`Payment` / `StripeEvent`** (existant) — réutilisés pour le paiement + webhook.
- **`PricingModel`** — objet de calcul (service, pas forcément table) : `quote(stay_draft)` → breakdown + total + acompte. Barème dégressif + supplément chien paramétrés (pas hardcodés en vue).

## 7. Intégrations & contraintes

- **Paiement :** Stripe Checkout + webhook `webhooks/stripe_hooks` (infra existante réutilisée). Acompte 50 % configurable. Test mode pour le system spec happy-path.
- **Email :** Postmark — lien token stable de consultation.
- **Auth :** Devise + `Role`/`HumanRole` (pas de Pundit/CanCan, contrôles `before_action`). `/reservation` est public (bypass Devise). Vue admin protégée Devise.
- **Persistance auditable :** soft_deletion + PaperTrail, **aucun hard-delete** (ISA P2 / ISC-15 / ISC-17).
- **Lodging composé :** réserver Grand-Duc bloque Hulotte + Chevêche, et inversement.
- **Calendrier +18 mois** pour Hulotte, Chevêche, Grand-Duc.
- **OTA :** Claudy = source de vérité, OTAs en aval (ISA Constraint). **T2 ne bloque PAS les dates OTA (Q6 tranchée NON)** — le blocage de dispo ne joue qu'entre Stays natifs Claudy.
- **i18n :** `/reservation` est **FR-only en T2 (Q7)** — pas de sélecteur de langue.
- **Déploiement :** Hatchbox sans staging — tranche déployable sans interruption, sans régression sur Stays tranche 1 / Tally legacy.
- **Hotwire-only :** `package.json` sans `react` / `vue` / `@inertiajs/*` (ISC-12).

## 8. Critères d'acceptation (testables par le Vérificateur)

> Un par ligne, atomique, vérifiable par une action concrète. Numérotation `AC-T2-NN` locale à la tranche 2. Chaque ligne dit comment l'ouvrir/le tester. Toutes les décisions Q1-Q9 sont **figées** (plus de blocage) — voir §11.

### Funnel `/reservation` — accessibilité & navigation
- [ ] AC-T2-01 : `GET /reservation` → `200` pour un visiteur **non authentifié Devise** (route publique). Vérif : `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/reservation` → 200, sans cookie de session.
- [ ] AC-T2-02 : Page 1 présente le sélecteur « infos » vs « réserver » ; « réserver » mène à l'étape dates par navigation Turbo (pas de full reload). Vérif : Interceptor — ouvrir `/reservation`, cliquer « réserver », transition d'étape sans rechargement complet.
- [ ] AC-T2-03 : Funnel full Hotwire — `cat package.json | jq '.dependencies + .devDependencies | keys'` ne contient ni `react`, ni `vue`, ni `@inertiajs/*` (ISC-12 préservé). Vérif : commande jq → 0 match.

### Calendrier & disponibilité
- [ ] AC-T2-04 : L'étape dates affiche un calendrier atteignable jusqu'à **≥ +18 mois** pour Hulotte, Chevêche, Grand-Duc. Vérif : Interceptor — naviguer jusqu'au mois M+18 ; il rend.
- [ ] AC-T2-05 : Les jours occupés par un Stay/Booking existant apparaissent indisponibles, cohérents avec `Lodging#available_between?`. Vérif : créer un Stay confirmé en fixture, ouvrir `/reservation`, la plage est marquée occupée pour le gîte.
- [ ] AC-T2-06 : Réserver le Grand-Duc marque Hulotte ET Chevêche occupées sur la plage (et inversement). Vérif : request/system spec sur `composed_of_lodgings` ; ou Interceptor (Hulotte occupée → Grand-Duc indispo).

### Catalogue & composition
- [ ] AC-T2-07 : Chaque option hébergement affiche nom, capacité, description courte, prix-soir indicatif ; le Grand-Duc porte « = Hulotte + Chevêche réservées ensemble ». Vérif : Interceptor — libellé visible sur la carte Grand-Duc.
- [ ] AC-T2-08 : Composition multi-items end-to-end : dates → hébergement → camping/options → salle(s) → repas → pre-order pain → coordonnées ; chaque ajout apparaît au panier. Vérif : system spec happy-path ajoutant ≥ 1 item par catégorie disponible.
- [ ] AC-T2-09 : Champ animal/chien obligatoire — soumettre coordonnées sans le renseigner échoue avec message de validation. Vérif : request/system spec — POST sans le champ → erreur ; avec → passe.
- [ ] AC-T2-09b : Le flow `/reservation` ne facture/ne gère automatiquement qu'**UN SEUL chien** (multi-chiens hors flow, traité manuellement par Malau, Q2). Vérif : system/request spec — sélectionner « plusieurs chiens » ne produit pas un supplément auto > 1× ; le flow oriente vers un traitement manuel (message/route) au lieu de calculer N × 50 €.

### Devis temps-réel & pricing
- [ ] AC-T2-10 : Le total TVAC du panier se met à jour à chaque modif **sans rechargement complet** (Turbo Frames/Streams). Vérif : Interceptor — ajouter un item, le total change sans GET document full-page (network).
- [ ] AC-T2-11 : Le devis affiche « pas de TVA en plus » (ou copy validé) près du total. Vérif : Interceptor — chaîne présente dans le DOM de l'étape panier.
- [ ] AC-T2-12 : `PricingModel.quote(stay_draft)` retourne breakdown ligne par ligne (label + montant TVAC), `total` TVAC, `deposit` (= 50 % par défaut). Vérif : model spec sur la structure de retour.
- [ ] AC-T2-13 : `PricingModel.quote` calcule correctement chaque structure de prix supportée (forfait/nuit, forfait/jour-ou-½journée, €/pers/nuit, forfait/nuit/véhicule, €/pers, forfait+€/pers). Vérif : model spec — un exemple par structure, montant attendu en dur depuis le barème documenté.
- [ ] AC-T2-14 : `PricingModel.quote` applique la **formule fermée dégressive par défaut** `prix = prix_nuit_1 + (n − 1) × prix_nuit_suivante`, paramétrée par hébergement (Q3). Vérif : model spec — Grand-Duc (`prix_nuit_1 = 750 €`, `prix_nuit_suivante = 600 €`) → **2n = 1 350 €**, **3n = 1 950 €**, **4n = 2 550 €**, **5n = 3 150 €**, **6n = 3 750 €** (montants en dur).
- [ ] AC-T2-14b : Un **forfait nommé écrase (override)** la formule pour la durée concernée (Q3 hybride). Vérif : model spec — Grand-Duc 7 nuits → **forfait « semaine » = 2 410 €** (et NON le résultat de la formule pour 7n), tandis que 4/5/6 nuits restent calculées par la formule.
- [ ] AC-T2-15 : `PricingModel.quote` applique le supplément chien **50 € / chien / séjour (Q2)** quand le champ animal indique un chien, **plafonné à un seul chien** dans le flow auto. Vérif : model spec — `quote(avec 1 chien) == quote(sans chien) + 50 €` ; `quote(avec 2 chiens)` ne facture pas automatiquement 100 € (multi-chiens hors flow auto, cf. AC-T2-09b).
- [ ] AC-T2-16 : L'acompte affiché et facturé Stripe = 50 % du total TVAC, valeur configurable (pas de littéral non paramétré en vue). Vérif : model/service spec sur l'acompte + grep absence de `0.5` hardcodé en vue.
- [ ] AC-T2-17 : Le breakdown de `PricingModel.quote` est la **même source** que le panier UI et le récap email. Vérif : service/request spec — le breakdown du quote correspond au contenu de l'email post-réservation.

### Customer, Stay, paiement
- [ ] AC-T2-18 : À la soumission, `Customer` upserté par email (lowercase) : email existant → Stay rattaché ; email nouveau → Customer créé. Vérif : request spec — deux soumissions même email = 1 Customer, 2 Stays.
- [ ] AC-T2-19 : **Validation manuelle Malau, PAS d'auto-confirm (Q5).** Paiement Stripe réussi (test mode) sur un Stay `/reservation` → le Stay reste `pending` (demande/draft à valider), il ne passe **jamais** automatiquement en `confirmed`. Le passage à `confirmed` n'a lieu que par une action interne explicite de Malau. Vérif : system/request spec test mode + webhook simulé — après paiement OK, `Stay#status == "pending"` ; une action admin dédiée le passe à `confirmed`.
- [ ] AC-T2-20 : Webhook Stripe `/webhooks/stripe_hooks` persiste un `StripeEvent` et met à jour le statut Stay/Payment pour un Stay créé via `/reservation`. Vérif : request spec POST webhook signé → `StripeEvent` créé + statut mis à jour (préserve ISC-4).
- [ ] AC-T2-21 : Après confirmation, email Postmark avec **lien token stable** envoyé au Customer ; ouvrir le lien sans Devise affiche le récap du Stay. Vérif : request/system spec — mail enqueued avec lien token ; GET du lien → 200 + récap, sans session Devise.

### Attribution de source & vue admin
- [ ] AC-T2-22 : Une **migration T2 ajoute la colonne `Stay#source` (string)** — absente du schema avant T2 — avec valeurs admises `reservation` / `tally_legacy` / `ota` / `manual` et **défaut `reservation`**. Vérif : `db/schema.rb` après migration contient `t.string "source"` sur `stays` ; model spec — un Stay créé sans source explicite a `source == "reservation"`.
- [ ] AC-T2-22b : Tout `Stay` créé via `/reservation` porte `source == "reservation"`, et `source` est **distinct de `legacy_origin`** (la migration ne réutilise ni n'écrase `legacy_origin`, qui garde son index unique). Vérif : request spec — Stay du funnel a `source == "reservation"` ; grep/migration review — `legacy_origin` inchangé, aucune confusion `source`/`legacy_origin` dans le code.
- [ ] AC-T2-23 : La vue admin liste les Stays récents et filtre par `source` (`/reservation` natif vs Tally legacy vs OTA). Vérif : Interceptor authentifié Devise — appliquer le filtre, la liste se restreint correctement.
- [ ] AC-T2-24 : La vue admin est protégée Devise — visiteur non authentifié redirigé vers `/users/sign_in` (préserve ISC-3). Vérif : `curl` sans session sur la route admin → 302 vers sign_in.

### Non-régression & coexistence
- [ ] AC-T2-25 : Les Stays Tally legacy restent consultables/payables via leur lien token `:public` existant (aucune régression). Vérif : system spec — Stay legacy fixture s'ouvre via son ancien lien token sans erreur.
- [ ] AC-T2-26 : Aucun hard-delete introduit — `grep -rn '\.destroy!\|delete_all' app/services app/controllers | grep -iE 'stay|customer|payment|booking'` → 0 hit non-tracé soft_deletion/PaperTrail (préserve P2 / ISC-15 / ISC-17). Vérif : grep → 0 hit.
- [ ] AC-T2-27 : Le déploiement sur `main` aboutit sur Hatchbox sans intervention manuelle et `/reservation` répond `200` en prod (préserve ISC-11). Vérif : push main → déploiement → `curl https://app.les4sources.be/reservation` → 200.

### Décisions de périmètre figées (Q4/Q6/Q7/Q8)
- [ ] AC-T2-29 : **Pre-order = lien externe (Q4).** L'étape pre-order affiche un **lien externe** vers `tranches-de-vie.les4sources.be` (post-réservation) et **n'effectue aucun appel write** à l'API Tranches de Vie. Vérif : Interceptor — le lien est présent et sort du domaine ; grep — aucun appel HTTP POST/PATCH vers l'API TDV dans le code du flow.
- [ ] AC-T2-30 : **FR-only (Q7).** `/reservation` ne présente **aucun sélecteur de langue** ; les libellés sont en français. Vérif : Interceptor — pas de switch FR/NL/EN dans le DOM du funnel.
- [ ] AC-T2-31 : **Pas de politique d'annulation dans le flow (Q8).** Aucune politique d'annulation/remboursement standardisée n'est affichée dans `/reservation`. Vérif : Interceptor — absence de bloc « politique d'annulation » dans les étapes du funnel.
- [ ] AC-T2-32 : **Pas de blocage OTA (Q6).** Une date occupée uniquement côté OTA (sans Stay natif Claudy) n'est pas marquée indisponible dans `/reservation` ; seuls les Stays natifs Claudy bloquent la dispo. Vérif : request/system spec — dispo calculée à partir des Stays/Bookings Claudy uniquement, pas d'une source OTA.

### Tests livrés avec la tranche
- [ ] AC-T2-28 : La suite contient model spec(s) PricingModel (dont formule dégressive + override forfait nommé + supplément chien) + service spec(s) booking flow + request spec(s) `/reservation/*` + **≥ 1 system spec happy-path B2C** (dates → composition → paiement Stripe test mode → Stay `pending` en attente de validation Malau). Vérif : `bundle exec rspec` vert ; fichiers spec présents.

## 9. Hypothèses à confirmer

- [HYPOTHÈSE] Le modèle `Stay` (tranche 1) expose déjà un `status` avec au moins `pending` et `confirmed`. À confirmer par le Constructeur ; sinon migration de statut nécessaire.
- [HYPOTHÈSE] L'infra Stripe Checkout + webhook existante (`namespace :public`) est réutilisable telle quelle pour un Stay `/reservation`, sans nouvelle clé/compte Stripe. Le BRIEF l'affirme — à confirmer en lisant `webhooks/stripe_hooks` + services `bookings/`.
- [HYPOTHÈSE] Le catalogue (gîtes, salles, repas, camping) est seedable depuis la spec Tally `reference_les4sources_tally_form.md` + matrice pricing ISA section G. Les libellés/copy client précis relèvent de la Plume.
- [HYPOTHÈSE] « +18 mois » = mois calendaires glissants depuis aujourd'hui (pas une date fixe). Cohérent avec la Constraint ISA.

## 10. Cohérence ISA & drifts BRIEF ↔ ISA

**ISC ISA préservés (non-régression) :** ISC-3 → AC-T2-24 · ISC-4 → AC-T2-20 · ISC-11 → AC-T2-27 · ISC-12 → AC-T2-03 · ISC-15/ISC-17 → AC-T2-26. Feature `BookingFlow` : T2 livre la variante `/reservation` (B2C) ; `/sejour-entreprise` (B2B) reste horizon. Feature `PricingModel` : T2 livre l'« étage 2 front B2C » + un « étage 1 backend » réduit aux structures observées ; polymorphisme complet, marges B2C/B2B, tranches de groupe, 6 packs et workshop d'audit des coûts restent horizon. Feature `Customers` : réutilisation de l'upsert par email (T1).

**Drifts — état après arbitrage Michael 2026-05-30 :**
- **DRIFT-1 — API studio READ-ONLY vs API v1 write — OUVERT, action de suivi (hors build T2).** La fiche `PROJETS-INTERNES.md` (Claudy) déclare l'accès API comme READ-ONLY (tous GET), alors que l'ISA (Changelog 2026-05-30, ISC-14.1, Feature `ApiV1`) et le BRIEF actent l'**écriture authentifiée** (PATCH + soft-delete). → La fiche studio est en retard sur l'ISA. **Sans impact sur le build T2** (ne touche pas l'API v1). **➡️ Action de suivi : mettre à jour `PROJETS-INTERNES.md` (Claudy) pour refléter l'API v1 write authentifiée.** La consigne « le studio n'écrit jamais en prod » reste valable indépendamment.
- **DRIFT-2 — `Stay#source` existant ou à créer ? — RÉSOLU (Q9).** Confirmé par `db/schema.rb` : la table `stays` n'a **PAS** de colonne `source` (elle a `legacy_origin`, distinct). → `source` est **ajouté par migration T2** (AC-T2-22/22b).
- **DRIFT-3 — Pre-order boulangerie : couplage API — RÉSOLU (Q4 = B).** Pre-order = **simple lien externe** post-réservation, pas de write API TDV (AC-T2-29).
- **DRIFT-4 — Posture auto-réservation — RÉSOLU (Q5 = B).** Pas d'auto-réservation : `/reservation` crée une demande/draft `pending` que **Malau valide manuellement** (AC-T2-19). Écart assumé vis-à-vis de la posture auto-réservation de l'ISA — voir Journal de décisions.
- **NON-DRIFT confirmé — Stack.** Hotwire verrouillé : BRIEF, ISA (P4, ISC-12), `PROJETS-INTERNES.md`, `CLAUDE.md` repo concordent. Aucune ambiguïté.

## 11. Questions de cadrage — RÉPONSES FIGÉES (Michael, 2026-05-30)

> Toutes tranchées. Plus aucun blocage build. Chaque décision pointe les AC concernés.

1. **Q1 — Coexistence `:public` (lien token) → OUI.** Les Stays Tally legacy gardent leur lien token `:public` existant (lecture + paiement acompte). Coexistence avec `/reservation`, pas de bascule forcée. → AC-T2-25.
2. **Q2 — Supplément chien → 50 € / chien / séjour.** Le flow auto ne facture qu'**UN seul chien** ; multi-chiens = **hors flow**, traité manuellement par Malau. → AC-T2-09b, AC-T2-15.
3. **Q3 — Barème forfait dégressif → HYBRIDE.** Formule fermée par défaut `prix = prix_nuit_1 + (n − 1) × prix_nuit_suivante` (paramétrée par hébergement) **+ forfaits nommés qui écrasent** pour certaines durées. Cas de test Grand-Duc : **nuit 1 = 750 €, nuits suivantes = 600 €, forfait « semaine » = 2 410 € (override)** ; la formule couvre 4-5-6 nuits automatiquement. → AC-T2-14, AC-T2-14b.
4. **Q4 — Pre-order épicerie/boulangerie → simple lien externe (B).** Lien vers `tranches-de-vie.les4sources.be` post-réservation, **pas d'intégration write API**. Résout DRIFT-3. → AC-T2-29.
5. **Q5 — Auto-réservation vs validation manuelle → validation manuelle Malau (B).** PAS d'auto-confirm. `/reservation` crée une demande/draft `pending` que Malau confirme. Résout DRIFT-4. → AC-T2-19.
6. **Q6 — OTA double-booking → NON.** T2 ne bloque pas les dates OTA ; blocage seulement entre Stays natifs Claudy. → AC-T2-32, §7.
7. **Q7 — i18n → FR-only.** Pas de sélecteur de langue en T2. → AC-T2-30, §4.
8. **Q8 — Annulation/remboursement → NON.** Pas de politique d'annulation affichée dans le flow en T2 (cas par cas hors flow). → AC-T2-31, §4.
9. **Q9 — Champ `source` sur Stay → AJOUTER par MIGRATION T2.** Colonne `source` (string), valeurs `reservation` / `tally_legacy` / `ota` / `manual`, **défaut `reservation`**. Confirmé absent du schema actuel. **DISTINCT de `legacy_origin`** (clé d'import/dédup à index unique, déjà présente — ne pas confondre ni réutiliser). Résout DRIFT-2. → AC-T2-22, AC-T2-22b.

## 12. Journal de décisions (append-only)

- 2026-05-30 — Stack frontend = Hotwire (verrouillé P4 + ISC-12). — *BRIEF §Décisions actées, Michael.*
- 2026-05-30 — Tranche 2 = option A : BookingFlow B2C natif + PricingModel minimal, sans B2B, sans packs. — *BRIEF §Décisions actées, Michael.*
- 2026-05-30 — API v1 write = doctrine (ISA Changelog + ISC-14.1) ; hors périmètre build T2. — *BRIEF §Décisions actées, Michael.*
- 2026-05-30 — PRD tranche 2 rédigé : 28 critères atomiques, 9 questions de cadrage, 4 drifts signalés. Remplace l'ancien `docs/PRD.md` (tranche 1 — historique préservé dans git). En attente validation Michael. — *sg-cadreur.*
- 2026-05-30 — **PRD VALIDÉ par Michael + Q1-Q9 tranchées.** Q1 OUI (coexistence lien token `:public`) · Q2 50 €/chien/séjour, 1 chien en flow auto / multi-chiens manuel · Q3 HYBRIDE (formule fermée + forfaits nommés override ; cas Grand-Duc 750/600/sem 2410) · Q4 B (pre-order = lien externe) · Q5 B (validation manuelle Malau, pas d'auto-confirm) · Q6 NON (pas de blocage OTA) · Q7 FR-only · Q8 NON (pas de politique d'annulation) · Q9 colonne `source` ajoutée par migration T2, distincte de `legacy_origin`. — *Michael.*
- 2026-05-30 — **Écart assumé vis-à-vis de l'ISA :** la posture auto-réservation de l'ISA (Feature `BookingFlow` B2C) est volontairement non appliquée en T2 — validation manuelle Malau retenue (Q5). À reverser éventuellement dans l'ISA si la posture devient durable. — *Michael / sg-cadreur.*
- 2026-05-30 — PRD figé : passage de 28 à **35 critères** (7 ajouts : AC-T2-09b, 14b, 22b, 29, 30, 31, 32 ; AC-T2-22 redéfini en place + AC-T2-22b ajouté pour la distinction `legacy_origin`). Statut → Validé, prêt pour le Constructeur. DRIFT-2/3/4 résolus ; DRIFT-1 reste action de suivi (mise à jour fiche `PROJETS-INTERNES.md`). — *sg-cadreur.*

---

## Porte humaine (FRANCHIE ✅)

Ce PRD est **validé par Michael (2026-05-30)** : (1) Q1-Q9 tranchées (§11) ; (2) DRIFT-2/3/4 résolus, DRIFT-1 acté comme action de suivi hors build ; (3) périmètre in/out-scope validé ; (4) « oui » explicite donné. **Le Constructeur, la Directrice Artistique, la Plume et le Vérificateur peuvent démarrer.**

**Action de suivi hors build (DRIFT-1) :** mettre à jour la fiche `~/.claude/PAI/USER/PROJECTS/StudioSuperGenial/PROJETS-INTERNES.md` (Claudy) — l'API y est dite READ-ONLY alors que l'ISA/BRIEF actent l'API v1 write authentifiée.

*Fin du PRD tranche 2.*
