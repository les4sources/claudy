# PRD — Claudy · Tranche 1 : Customers + StayComposite + LegacyBookingMigration

> Contrat de passation du studio Super Génial. Produit par le Cadreur depuis `docs/BRIEF.md` + `ISA.md`, **validé par Michael avant tout build**. Tous les agents lisent ce fichier. Vit dans le repo client (`docs/PRD.md`), versionné.
> Source de vérité long-lived = `~/code/claudy/ISA.md`. Ce PRD est une **vue dérivée scopée à la tranche 1** — il ne couvre qu'un sous-ensemble de l'ideal state (Features `Customers`, `StayComposite`, `LegacyBookingMigration`). Ne pas déborder.

- **Statut :** **validé** — les 8 décisions §11 sont verrouillées (2026-05-28). Porte fermée, build autorisé. Aucune question ouverte.
- **Repo :** github.com/les4sources/claudy · **Branche déploiement :** main · **Déploiement :** Hatchbox → Linode VPS (pas de staging)
- **Stack :** Ruby on Rails 7.0 · Ruby 3.1.2 · PostgreSQL · Node 18.8.0 · Vite (`vite_rails`)
- **Stack frontend : `Hotwire`** (Turbo + Stimulus + Slim, server-rendered). Verrouillée par ISA P4 + ISC-12 (anti-criterion : aucun `react` / `vue` / `@inertiajs/*` dans `package.json`). Aucune dérogation. — *ligne lue par Constructeur et Vérificateur, ne pas omettre.*
- **Stratégie :** strangler pattern (Décision ISA 2026-05-28) — on étend l'app en prod, **pas de rewrite**. Tranche 1 = pivot architectural pur, additif, coexistence ancien/nouveau.

---

## 1. Problème & objectif

Aujourd'hui dans Claudy, le client n'est pas une entité : son email est un champ libre dupliqué sur chaque `Booking` et `SpaceBooking`, sans normalisation ni clé unique. Conséquence : impossible de voir l'historique d'un même client, de détecter la récurrence B2B (~60 % des clients B2B reviennent — cf. analyse inbox), d'offrir un portail self-service, ou de raisonner « panier » sur un séjour qui mélange hébergement + salle. La tranche 1 pose la **fondation du modèle de données** — `Customer` (entité de premier ordre, clé `email`) et `Stay` (tête d'un graphe d'items réservables polymorphes) — et **migre tout l'historique** existant dessus, sans changer aucun flow utilisateur visible et sans interruption de prod. Toutes les tranches suivantes (BookingFlow natif, PricingModel, packs B2B, B2bCrm, NPS, GuestMobileApp) s'appuieront sur cette fondation.

**Objectif mesurable :** après bascule, **100 %** des `Booking` + `SpaceBooking` (actifs, passés, annulés, soft-deleted, **y compris ceux sans email exploitable** — rattachés au Customer fourre-tout `client@les4sources.be`) sont rattachés à un `Stay` et un `Customer`, zéro perte de donnée historique, idempotence prouvée, zéro régression sur les flows existants (booking public + Stripe).

## 2. Utilisateurs / audience

Aucun nouvel utilisateur final visible n'est introduit par cette tranche (pivot interne). Les surfaces touchées :

- **Pôle Accueil** (Malau + collectif, authentifié Devise) — consommateurs des **nouvelles vues admin Customer** : recherche par email/nom, vue historique d'un client, édition des notes internes, **fusion de doublons** (sert aussi à **re-ventiler** les Stays du Customer fourre-tout `client@les4sources.be` vers de vrais clients).
- **Agents IA** (Bee + agents internes, Bearer `AGENT_API_TOKEN`) — consommateurs des **nouveaux endpoints API read-only** `/api/v1/customers/:id` et `/api/v1/stays/:id` (P1 : tout modèle métier a sa surface agent).
- **Mainteneur / opérateur de migration** (Michael) — exécute la rake task d'audit, de migration (dry-run + réel) et lit le rapport post-migration.
- **Hors tranche** : le client final (pas de portail self-service ici), le flow B2C/B2B natif (tranche 2).

## 3. Périmètre

Trois features, additives, déployables progressivement sur prod active.

### 3.1 — `Customer` (modèle + vues admin minimales + fusion de doublons)
- Nouveau modèle ActiveRecord `Customer`, entité de premier ordre (distinct de `Human` = membres du collectif).
- Clé d'unicité : `email`, type **citext**, normalisé en lowercase + trim avant validation/persistance.
- `soft_deletion` (default_scope) + `PaperTrail` (cohérent ISA P2 / ISC-15/17).
- Vues admin Pôle Accueil en **Hotwire/Slim** (Draper + ViewComponent où pertinent) : index recherchable (email/nom), show avec historique des stays, edit des `notes`, **fusion de doublons** (merge des associations sur un Customer cible + soft-delete de la source + trace PaperTrail).
- Endpoint API read-only `GET /api/v1/customers/:id` (+ index) via jbuilder + entrée OpenAPI `config/openapi/v1.yaml`.

### 3.2 — `Stay` (StayComposite : tête d'un graphe d'items réservables)
- Nouveau modèle `Stay`, `belongs_to :customer`, agrège des **items réservables polymorphes** (`stay_items`).
- Tranche 1 : seuls `Booking` (hébergement) et `SpaceBooking` (salle) existent comme items. Les 6 autres types (`ActivityBooking`, `EventBooking`, `MealOrder`, `BakeryOrder`, `BarCharge`, `GroceryCharge`) sont **hors-scope** — l'association polymorphe doit juste être extensible sans refonte.
- `soft_deletion` + `PaperTrail`.
- Mécanique **Lodging composé** (Grand-Duc = Hulotte + Chevêche) : self-referential `composed_of_lodgings` sur `Lodging` + logique de blocage de disponibilité (réserver Grand-Duc bloque H + C, et inversement).
- Endpoint API read-only `GET /api/v1/stays/:id` (+ index) via jbuilder + entrée OpenAPI.

### 3.3 — `LegacyBookingMigration` (script rake idempotent + dry-run + rapport)
- Audit pré-migration → rake task `claudy:migrate:legacy_bookings_to_stays` → rapport post-migration.
- Fenêtre = **tout l'historique** (décidé) : actifs + passés + annulés + soft-deleted ; les bookings **sans email exploitable** (vide, malformé, ou masqué OTA `*@guest.*`) sont **rattachés au Customer fourre-tout** `client@les4sources.be` (upsert idempotent), **pas skippés** (décision verrouillée §11.2).
- Pour chaque Booking/SpaceBooking : déterminer l'email exploitable → si exploitable, upsert `Customer` par email lowercase ; sinon, upsert le `Customer` fourre-tout `client@les4sources.be` → crée un `Stay` si pas déjà migré (marqueur `legacy_*_id` idempotent) → attache le booking comme `stay_item`.
- **Customer fourre-tout** créé/upserté par la migration : `email = client@les4sources.be`, `customer_type = individual`, `language = fr`, `first_name = "Client"`, `last_name = "Les 4 Sources"`, `notes` marquant son rôle (« fourre-tout migration — re-ventiler via fusion de doublons »). Re-ventilation ultérieure des Stays par le Pôle Accueil **via le mécanisme de fusion de doublons** (§3.1).
- Préservation PaperTrail **et** PublicActivity (les deux sont actifs sur Booking/SpaceBooking) ; ne supprime aucune version existante.
- Feature transitoire (archivée après bascule).

## 4. Hors-périmètre (anti-dérive) — repris du brief, sans exception

- **Pas de forms natifs Claudy** (`/reservation` B2C, `/sejour-entreprise` B2B) — tranche 2.
- **Pas de PricingModel polymorphe** — tranche ultérieure (tracé horizon dans l'ISA).
- **Pas de packs B2B prédéfinis** — découle du PricingModel.
- **Pas d'AutoAcknowledgement / Faq / B2bCrm / PostStayNps / PublicApi / GuestMobileApp / Kiosk / Reporting / BudgetTracking / BarAndGrocery / Bakery (TDV) / Activities / Events / ScopedExternalAccess** — toutes horizon, tranches dédiées.
- **Pas de portail self-service client** (consultation/factures/préférences via lien token) — tranche future, même si `Customer` est conçu pour le supporter.
- **Pas de refonte UI** — l'admin Pôle Accueil garde Hotwire/Slim existant ; on n'étend que les vues des nouveaux modèles.
- **Pas de migration vers Rails 8** — on reste Rails 7 + Ruby 3.1.2.
- **Pas de write API** (`Api::V1` reste read-only ; ajout des seuls nouveaux modèles en GET — ISC-14).
- **Pas de cutover définitif des anciens controllers Booking/SpaceBooking** dans cette tranche — coexistence durant la transition ; le retrait de l'ancien chemin est une décision ultérieure de Michael après période d'observation.
- **Pas de déduplication automatique en masse** au-delà du merge manuel par le Pôle Accueil (la détection automatique de doublons fins type OTA n'est pas livrée — décision verrouillée §11.3). Inclut la re-ventilation des Stays rattachés au Customer fourre-tout `client@les4sources.be` : elle se fait **manuellement** via la fusion de doublons, pas automatiquement.

## 5. Pages & parcours (sitemap)

Surfaces admin nouvelles (authentifiées Devise, hors `namespace :public` et `:api`) :

- `GET /customers` — index recherchable (email / nom), paginé. Hotwire/Slim.
- `GET /customers/:id` — show : coordonnées, `customer_type`, historique des stays (à venir / passés), paiements agrégés (via stays), notes internes.
- `GET /customers/:id/edit` + `PATCH /customers/:id` — édition coordonnées + `notes` (rich text).
- **Fusion de doublons** — parcours : sélection de 2 Customers (source + cible) → écran de confirmation listant ce qui sera transféré (stays, human link, stripe_customer_id) → exécution → source soft-deleted, cible enrichie, entrée PaperTrail. (Mécanique UI précise à arbitrer DA/Constructeur ; le PRD fixe le comportement, pas le pixel.)

Surfaces API nouvelles (read-only, Bearer) :

- `GET /api/v1/customers` + `GET /api/v1/customers/:id`
- `GET /api/v1/stays` + `GET /api/v1/stays/:id`

Aucune page publique (`namespace :public`) nouvelle. Calendrier inchangé.

## 6. Modèle de données (pressenti, Rails)

> Tous les choix de modélisation ci-dessous sont **validés** (décisions §11, hypothèses §9 confirmées le 2026-05-28). Plus aucun `[HYPOTHÈSE]` ouvert.

### `customers`
| champ | type | notes |
|---|---|---|
| `id` | bigint PK | |
| `first_name` | string | |
| `last_name` | string | |
| `email` | **citext** | **unique** (index unique), normalisé lowercase + trim, validation format RFC |
| `phone` | string | normalisé E.164 |
| `customer_type` | string/enum | `individual` \| `organization` |
| `organization_name` | string | requis si `organization` |
| `vat_number` | string | optionnel |
| `peppol_id` | string | optionnel |
| `address_line`, `address_zip`, `address_city`, `address_country` | string | optionnels (requis pour facture, tranche future) |
| `language` | string/enum | `fr` \| `nl` \| `en` (défaut `fr` — décision §11.8 ; pas de détection auto) |
| `stripe_customer_id` | string | réutilisable d'un séjour à l'autre |
| `notes` | rich text (ActionText) | interne Pôle Accueil + collectif uniquement (décision §11.7) ; jamais client/API publique |
| `marketing_consent` | boolean | défaut false (RGPD) |
| `nps_eligible` | boolean | défaut false |
| `human_id` | bigint FK nullable | `belongs_to :human, optional: true` |
| `deleted_at` | datetime | soft_deletion |

- `has_many :stays` ; `has_many :payments, through: :stays` ; `belongs_to :human, optional: true`.
- `has_paper_trail` + `has_soft_deletion default_scope: true`.
- `Customer.normalize_email(raw)` — point unique de normalisation, réutilisé par la migration.

> **Customer fourre-tout (décision §11.2).** Un Customer conventionnel unique d'email `client@les4sources.be` recueille tous les bookings legacy **sans email exploitable** (vide, malformé, ou masqué OTA `*@guest.*`). Attributs imposés : `customer_type = individual`, `language = fr`, `first_name = "Client"`, `last_name = "Les 4 Sources"`, `notes` marquant son rôle. Il se distingue d'un vrai client par son email conventionnel (pivot pour le requêter) et par sa note. Upsert idempotent comme les autres Customers (la migration ne le crée qu'une fois). Re-ventilation de ses Stays vers de vrais Customers = fusion de doublons manuelle (§3.1), jamais auto.

### `stays`
| champ | type | notes |
|---|---|---|
| `id` | bigint PK | |
| `customer_id` | bigint FK | `belongs_to :customer` |
| `arrival_date` | date | min des dates des items |
| `departure_date` | date | max des dates des items |
| `status` | string/enum | dérivé/agrégé du statut des items (valeurs à aligner sur Booking : `pending`/`confirmed`/`declined`/`canceled`) |
| `total_amount_cents` | integer | somme des items (monetize) |
| `notes` | text | |
| `legacy_origin` | string nullable | marqueur de provenance migration (audit) |
| `deleted_at` | datetime | soft_deletion |

- `has_many :stay_items` (polymorphe : `bookable_type` / `bookable_id` → `Booking`, `SpaceBooking`, …).
- `has_many :payments, through: :stay_items` (dérivé en lecture — décision §11.6, voir note ci-dessous).
- `has_paper_trail` + `has_soft_deletion default_scope: true`.

### `stay_items` (table de jointure polymorphe)
| champ | type | notes |
|---|---|---|
| `id` | bigint PK | |
| `stay_id` | bigint FK | |
| `bookable_type` | string | `Booking` \| `SpaceBooking` (extensible) |
| `bookable_id` | bigint | + index unique `(stay_id, bookable_type, bookable_id)` |
| `deleted_at` | datetime | soft_deletion |

> **Note paiements (contrainte dure relevée dans le code).** `Payment.booking_id` est **NOT NULL** et `Payment belongs_to :booking`. `SpaceBooking` ne porte pas de `Payment` (montants stockés en colonnes `*_amount_cents`). Donc `Customer.payments through: :stays` ne peut PAS s'appuyer sur une FK `payment.stay_id` sans migration de schéma de `Payment` — hors-scope. **Reco tranche 1 :** dériver `Customer#payments` / `Stay#payments` via la chaîne `stay → stay_items (Booking) → booking.payments` (lecture), sans toucher la table `payments`. Le brief écrit `has_many :payments, through: :stays` ; on l'honore au niveau de l'API lue, pas au niveau d'une nouvelle FK. **Décision verrouillée §11.6 : OUI** (dérivation lecture, schéma `payments` intact, `Payment.booking_id` reste NOT NULL).

### Champs ajoutés aux modèles existants (additifs, non destructifs)
- `Lodging` : association self-referential `composed_of_lodgings` (table de jointure `lodging_compositions` : `composite_lodging_id`, `component_lodging_id`) → Grand-Duc.composed_of = [Hulotte, Chevêche]. **Aucune** colonne supprimée.
- `Booking` / `SpaceBooking` : `has_one :stay_item` + `has_one :stay, through: :stay_item` (lecture inverse). Pas de FK directe imposée pour préserver la coexistence.

## 7. Intégrations & contraintes

- **Paiement Stripe** — inchangé. `Payment` non modifié (schéma préservé). `stripe_customer_id` ajouté sur `Customer` sans recâbler le flow Stripe existant.
- **Email Postmark** — inchangé (aucun nouveau mail dans cette tranche).
- **Auth** — Devise + role models pour l'admin ; Bearer `AGENT_API_TOKEN` pour l'API. Pas de Pundit/CanCan ; contrôles en `before_action` (convention repo).
- **API read-only** — nouveaux endpoints en GET uniquement (P1 + ISC-14). OpenAPI `config/openapi/v1.yaml` mis à jour. Jamais d'exposition `stripe_payment_intent_id` / `stripe_checkout_session_id` (ISC-9). Soft-deleted absents des réponses (ISC-8).
- **Audit (P2, contrainte forte)** — Booking/SpaceBooking ont **DEUX** systèmes de traçabilité actifs : `has_paper_trail` **et** `PublicActivity::Model` (`tracked owner:`). La migration doit préserver les deux historiques. Nouveaux modèles : PaperTrail (PublicActivity non requis).
- **Coexistence sans interruption** — Claudy est en prod active, pas de fenêtre de maintenance. Migrations DB additives (create_table, add_column, add FK nullable) — aucune colonne/table retirée. Anciens controllers Booking/SpaceBooking fonctionnels pendant toute la tranche.
- **Tests (opportunité)** — le repo n'a **pas** de suite de tests aujourd'hui (RSpec présent, specs `models/` + `components/` minimaux). Tout le **nouveau** code (Customer, Stay, StayItem, composition Lodging, migration rake) DOIT être couvert par model specs + request specs (sous `spec/requests/api/v1/`). Pas d'obligation de tester l'existant.
- **Déploiement** — `git push main` → Hatchbox déploie + `db:migrate`. Le post-migration check doit être vert.

## 8. Critères d'acceptation (testables par le Vérificateur)

> Atomiques, vérifiables individuellement, mappables à un model/request spec ou une probe shell.

### A. Modèle `Customer`
- [ ] AC-1: Une migration crée la table `customers` avec une colonne `email` de type **citext** et un **index unique** sur `email` (`\d customers` montre `citext` + `UNIQUE`).
- [ ] AC-2: `Customer.create!(email: "  Foo@Bar.COM ")` persiste `email == "foo@bar.com"` (normalisation lowercase + trim).
- [ ] AC-3: Créer deux Customers avec le même email (casse/espaces différents) lève une erreur de validation d'unicité — le second n'est pas persisté.
- [ ] AC-4: Un email au format invalide (`"pas-un-email"`) échoue la validation d'un Customer créé directement (hors migration). En migration, un email invalide/vide/OTA-masqué n'échoue pas : le booking est routé vers le Customer fourre-tout `client@les4sources.be` (cohérent avec AC-37 et AC-47).
- [ ] AC-5: `customer_type` n'accepte que `individual` ou `organization` ; une autre valeur échoue.
- [ ] AC-6: Un `Customer` `organization` sans `organization_name` échoue la validation ; un `individual` sans `organization_name` passe.
- [ ] AC-7: `Customer` a `has_many :stays`, `belongs_to :human (optional)` ; `customer.human` peut être nil sans erreur.
- [ ] AC-8: Soft-delete d'un Customer (`soft_delete!`) le retire du default scope (`Customer.all` ne le renvoie pas) sans suppression physique (`Customer.unscoped` le retrouve) et crée une version PaperTrail.
- [ ] AC-9: Une modification d'un champ Customer crée une version PaperTrail (`customer.versions.count` augmente de 1).

### B. Vues admin Customer (Hotwire/Slim)
- [ ] AC-10: `GET /customers` non authentifié redirige vers `/users/sign_in` (ISC-3) ; authentifié rend 200 avec la liste.
- [ ] AC-11: La recherche `/customers?q=<fragment email ou nom>` retourne les Customers correspondants (insensible à la casse).
- [ ] AC-12: `GET /customers/:id` affiche l'historique des stays du client (à venir + passés distincts) et ses notes internes.
- [ ] AC-13: `PATCH /customers/:id` met à jour les `notes` (rich text) et persiste ; une version PaperTrail est créée.
- [ ] AC-14: Le `package.json` ne contient ni `react`, ni `vue`, ni `@inertiajs/*` après l'ajout de ces vues (ISC-12) — `jq '.dependencies|keys'` vide de ces clés.

### C. Fusion de doublons
- [ ] AC-15: Fusionner Customer source S dans cible C ré-affecte **tous** les `stays` de S vers C (aucun stay orphelin, `C.stays` inclut désormais ceux de S).
- [ ] AC-16: Après fusion, S est soft-deleted (absent du default scope, présent en `unscoped`), C est intact/enrichi.
- [ ] AC-17: La fusion crée une trace PaperTrail sur S (soft-delete) et sur les stays réaffectés (changement de `customer_id`).
- [ ] AC-18: Le `human_id` et le `stripe_customer_id` sont conservés sur la cible selon une règle déterministe documentée (cible prioritaire ; source utilisée seulement si cible vide) — vérifiable sur un cas où seule la source porte la valeur.
- [ ] AC-50: **Re-ventilation depuis le fourre-tout** — sélectionner un Stay rattaché au Customer fourre-tout `client@les4sources.be` et le ré-affecter vers un vrai Customer passe par **le même mécanisme de fusion/merge** (pas de chemin spécial) : le Stay est transféré, tracé PaperTrail (changement de `customer_id`), et le fourre-tout reste actif (non soft-deleted) tant qu'il porte encore d'autres Stays.

### D. Modèle `Stay` + StayItem + Lodging composé
- [ ] AC-19: Une migration crée `stays` (FK `customer_id`) et `stay_items` (polymorphe `bookable_type`/`bookable_id`) avec index unique `(stay_id, bookable_type, bookable_id)`.
- [ ] AC-20: Un `Stay` peut agréger un `Booking` **et** un `SpaceBooking` comme items ; `stay.stay_items.count == 2` et `stay.bookables` renvoie les deux objets.
- [ ] AC-21: `stay.arrival_date` / `stay.departure_date` reflètent le min/max des dates des items agrégés.
- [ ] AC-22: `Stay` + `StayItem` portent `soft_deletion` + `PaperTrail` (soft-delete retire du scope, crée une version).
- [ ] AC-23: `Lodging` expose `composed_of_lodgings` ; `Lodging.find_by(name:"Le Grand-Duc").composed_of_lodgings` renvoie La Hulotte + La Chevêche (seedé/migré).
- [ ] AC-24: Réserver (confirmé) le Grand-Duc sur une fenêtre rend Hulotte ET Chevêche **indisponibles** sur cette même fenêtre (`Lodging#available_between?` retourne false pour H et C). Comportement **calculé à la volée** (décision §11.4), sans blocage stocké ni réservation dupliquée.
- [ ] AC-25: Réserver (confirmé) la Hulotte rend le Grand-Duc indisponible sur la même fenêtre (dérivation inverse calculée : Grand-Duc dispo ⟺ Hulotte ET Chevêche libres).
- [ ] AC-26: La disponibilité d'un lodging **non composé** (ex. Tiny) est inchangée par rapport au comportement actuel (non-régression : même résultat avant/après sur un échantillon).
- [ ] AC-51: Les **requêtes de disponibilité existantes** (calendrier + `available_between?`) intègrent la composition Grand-Duc/Hulotte/Chevêche **par calcul à la volée**, sans colonne de blocage stockée ni réservation dupliquée (décision §11.4) : un grep confirme l'absence de réservation miroir créée pour le composite, et la dispo de Grand-Duc se dérive en lecture de l'état de Hulotte + Chevêche.

### E. API read-only
- [ ] AC-27: `GET /api/v1/customers/:id` sans Bearer → 401 ; avec Bearer valide → 200 + JSON du customer (ISC-6).
- [ ] AC-28: `GET /api/v1/stays/:id` avec Bearer valide → 200 + JSON du stay incluant ses items et leurs types.
- [ ] AC-29: Les réponses API customers/stays n'exposent jamais `stripe_payment_intent_id` ni `stripe_checkout_session_id` (`grep -ri` sur `app/views/api/v1/customers app/views/api/v1/stays` → vide) (ISC-9).
- [ ] AC-30: Un Customer / Stay soft-deleted est absent des réponses API (`/api/v1/customers` et `:id` → 404/absent) (ISC-8).
- [ ] AC-31: Toute écriture (`POST /api/v1/customers`, `POST /api/v1/stays`) → 404/405 (read-only, ISC-14).
- [ ] AC-32: `config/openapi/v1.yaml` contient les chemins `/customers/{id}` et `/stays/{id}` (P1 / ISC-16).

### F. Migration legacy (idempotence + zéro perte)
- [ ] AC-33: `rake claudy:migrate:legacy_bookings_to_stays DRY_RUN=true` (ou flag équivalent) n'écrit rien en base et imprime le rapport prévisionnel.
- [ ] AC-34: Après migration réelle, **chaque** `Booking` et `SpaceBooking` (incluant passés, annulés, soft-deleted, **et ceux sans email exploitable**) est rattaché à exactement un `Stay` via un `StayItem` — couverture 100 %, aucun booking orphelin.
- [ ] AC-35: Pour chaque email unique (lowercase) il existe exactement un `Customer` ; deux bookings au même email (casse/espace différents) pointent vers le même Customer.
- [ ] AC-36: **Idempotence** — relancer la tâche une 2ᵉ fois ne crée aucun nouveau `Customer`, `Stay` ni `StayItem` (compteurs identiques avant/après le 2ᵉ run).
- [ ] AC-37: Les bookings **sans email exploitable** (vide, malformé, ou masqué OTA `*@guest.*`) sont migrés et rattachés au Customer fourre-tout `client@les4sources.be` ; ils sont comptés dans le rapport (catégorie `n_rattaches_fourretout`). Aucun booking n'est skippé.
- [ ] AC-38: Aucune perte historique — pour un échantillon de bookings, dates / montants / statuts / paiements restent identiques après migration (le Booking source est inchangé, seulement rattaché).
- [ ] AC-39: PaperTrail préservé — `booking.versions` existant avant migration est toujours présent après ; **PublicActivity** (`booking.activities` ou équivalent) également préservé.
- [ ] AC-40: La création du `Stay`-parent par la migration est tracée PaperTrail attribuée au whodunnit `"system:migration"` (décision §11.5) — `stay.versions.last.whodunnit == "system:migration"`.
- [ ] AC-41: Le rapport post-migration ventile : `n_stays_créés`, `n_customers_créés`, `n_customers_upsertés`, et par catégorie booking `n_actifs / n_passés / n_annulés / n_soft_deleted / n_rattaches_fourretout`.
- [ ] AC-47: Après migration, il existe **exactement un** Customer d'email `client@les4sources.be` ; ses attributs sont `customer_type == "individual"`, `language == "fr"`, `first_name == "Client"`, `last_name == "Les 4 Sources"`, et ses `notes` mentionnent son rôle de fourre-tout migration (décision §11.2).
- [ ] AC-48: **Idempotence du fourre-tout** — relancer la migration ne crée pas de second Customer `client@les4sources.be` (compteur identique) et ne duplique aucun StayItem déjà rattaché au fourre-tout.
- [ ] AC-49: Tous les Stays issus de bookings sans email exploitable pointent vers le Customer fourre-tout ; un booking porteur d'un email OTA **exploitable et distinct** (ex. `jean.x9z@guest.airbnb.com` valide au format) crée **son propre** Customer et **n'est pas** rattaché au fourre-tout (pas de dédup fine — décision §11.3).

### G. Non-régression (coexistence)
- [ ] AC-42: Le flow de réservation public (`namespace :public`) jusqu'au paiement Stripe fonctionne à l'identique après la tranche (ISC-2 — vérif Interceptor sur prod-like).
- [ ] AC-43: La page calendrier (`pages#calendar`) affiche bookings + space_bookings comme avant, sans erreur (ISC-5).
- [ ] AC-44: Le calendrier de disponibilité sur une fenêtre donnée est **identique** avant et après migration pour les lodgings non composés (probe : comparaison `available_between?` sur échantillon de dates).
- [ ] AC-45: Aucun appel `destroy!` / `delete_all` n'est introduit sur Customer/Stay/StayItem/Booking/SpaceBooking/Payment (ISC-15/17 — `grep` ciblé → 0 hit non tracé).
- [ ] AC-46: Le déploiement Hatchbox sur `main` aboutit, `db:migrate` s'applique, et le post-migration check est vert (ISC-11).

## 9. Hypothèses — toutes confirmées (2026-05-28)

> Les hypothèses Q1→Q9 ont été tranchées par Michael (voir §11). Plus aucune n'est ouverte. Conservées ici comme faits actés pour le Constructeur et le Vérificateur.

- ✅ `Stay` est un **nouveau modèle distinct** ; `Booking`/`SpaceBooking` deviennent des `stay_items` (pas de transformation de Booking en Stay-parent). Conforme à la doctrine ISA. (§11.1)
- ✅ `Customer#payments` / `Stay#payments` sont **dérivés en lecture** via `stay_items → booking → payments`, sans nouvelle FK `payment.stay_id` ni modification du schéma `Payment`. (§11.6)
- ✅ La mécanique Grand-Duc est **calculée à la volée** (dispo composite = f(composants libres), et inversement), sans blocage stocké ni callbacks dupliquant des réservations. (§11.4)
- ✅ Les bookings **sans email exploitable** sont **rattachés au Customer fourre-tout** `client@les4sources.be` (upsert idempotent), **pas skippés** ; le Pôle Accueil re-ventile ensuite via fusion de doublons. (§11.2 — ⚠️ changement vs hypothèse initiale « skip »)
- ✅ La création du Stay-parent par la migration est tracée PaperTrail avec whodunnit `"system:migration"`. (§11.5)
- ✅ `Customer.notes` est **interne Pôle Accueil + collectif uniquement** ; jamais exposé au client ni à l'API publique future. (§11.7)
- ✅ `Customer.language` par défaut `fr`, renseigné explicitement plus tard ; pas de détection auto dans cette tranche. (§11.8)
- ✅ La déduplication OTA fine (même guest via Airbnb `*@guest.airbnb.com` + direct) **n'est pas automatisée** ; ces doublons restent gérables via la fusion manuelle. (§11.3)
- ✅ `status` de `Stay` est dérivé/agrégé des statuts des items (valeurs alignées sur Booking) ; pas de machine à états indépendante en tranche 1. (acté — non contesté)

## 10. Journal de décisions (append-only)

- 2026-05-28 — **Stack frontend = Hotwire**, verrouillée — source : ISA P4 + ISC-12, fiche PROJETS-INTERNES, `package.json` du repo. Aucune dérogation possible.
- 2026-05-28 — **Périmètre = pivot architectural pur** (data model + migration), aucun flow visible modifié — source : brief + décisions Michael 2026-05-28.
- 2026-05-28 — **Fenêtre de migration = tout l'historique** (actifs + passés + annulés + soft-deleted ; sans-email skippés/ventilés) — décidé par Michael (brief Q6).
- 2026-05-28 — **Vues Customer = minimal + fusion de doublons** — décidé par Michael.
- 2026-05-28 — **Hors-scope confirmé sans exception** (toutes features horizon) — décidé par Michael.
- 2026-05-28 — **Constat code : double traçabilité** sur Booking/SpaceBooking (`PaperTrail` + `PublicActivity`). La migration doit préserver les DEUX — élève la barre de l'AC-39 vs le brief qui ne mentionnait que PaperTrail.
- 2026-05-28 — **Constat code : `Payment.booking_id` NOT NULL**, `SpaceBooking` sans Payment. → `payments through: :stays` dérivé en lecture, pas de FK ajoutée (proposition, à valider Q9).
- 2026-05-28 — **Tests : tout nouveau code couvert** (model + request specs), pas d'obligation sur l'existant — source : brief.
- 2026-05-28 — **Porte §11 fermée : 8 décisions verrouillées par Michael.** Q1=OUI (Stay distinct), Q3=NON (dédup OTA manuelle), Q4=CALCULÉ (Grand-Duc à la volée), Q5=OUI (`system:migration`), Q6=OUI (payments dérivés lecture), Q7=OUI (notes internes), Q8=OUI (`fr` par défaut) — tous conformes aux recos.
- 2026-05-28 — **Q2 : CHANGEMENT vs reco.** Les bookings sans email exploitable ne sont **pas skippés** mais **rattachés à un Customer fourre-tout unique** `client@les4sources.be` (upsert idempotent ; `individual` / `fr` / "Client" / "Les 4 Sources" + note de rôle). Re-ventilation ultérieure via la **fusion de doublons** (même merge). Rapport : `n_sans_email_skipped` → `n_rattaches_fourretout`. Impacts AC : AC-4, AC-34, AC-37, AC-41 corrigés ; AC-47/48/49 (fourre-tout) et AC-50 (re-ventilation par fusion) ajoutés.
- 2026-05-28 — **Q4 implication actée : adaptation des requêtes de disponibilité existantes** (calendrier + `available_between?`) pour dériver Grand-Duc par calcul — nouvel AC-51.

## 11. Décisions verrouillées (2026-05-28)

> Les 8 questions ouvertes ont été **tranchées par Michael le 2026-05-28**. Aucune question ouverte ne subsiste. Porte fermée — prêt pour le Constructeur.

1. **Stay = nouveau modèle distinct, Booking devient un `stay_item`** (pas de transformation de Booking en Stay-parent). — **VERROUILLÉ : OUI**. Conforme ISA, additif, préserve la coexistence et les controllers existants.
2. **Bookings sans email exploitable → rattachés à un Customer fourre-tout unique** (et **non** skippés). — **VERROUILLÉ : fourre-tout**, ⚠️ *changement vs reco initiale (skip)*. Tout Booking/SpaceBooking dont l'email est inexploitable (vide, malformé, ou masqué OTA type `*@guest.booking.com` / `*@guest.airbnb.com`) est rattaché à **un Customer fourre-tout unique d'email `client@les4sources.be`**, upsert idempotent comme les autres Customers. Les emails OTA **distincts mais exploitables** créent leurs propres Customers (pas de dédup fine — voir point 3) ; seuls les emails **inexploitables** tombent dans le fourre-tout. Attributs du fourre-tout : `customer_type = individual`, `language = fr`, `first_name = "Client"`, `last_name = "Les 4 Sources"`, marqueur distinctif via l'email conventionnel `client@les4sources.be` **et** une mention en `notes` (« Customer fourre-tout migration — re-ventiler les stays vers de vrais clients via fusion de doublons »). Le Pôle Accueil re-ventile ensuite chaque Stay vers un vrai Customer **via le mécanisme de fusion de doublons** (le même merge que C — voir §3.1 et AC-15→18).
3. **Déduplication OTA fine** automatisée dans cette tranche ? — **VERROUILLÉ : NON**. Fusion **manuelle** uniquement par le Pôle Accueil. Pas d'auto-détection cette tranche (l'auto-dédup OTA nécessite une stratégie de matching nom+dates → tranche dédiée).
4. **Grand-Duc : disponibilité CALCULÉE à la volée** (dispo composite = f(composants libres), aucun blocage stocké) ? — **VERROUILLÉ : CALCULÉ**. La dispo de Grand-Duc se dérive de Hulotte + Chevêche libres ; aucune réservation dupliquée, une seule source de vérité. Implique d'**adapter les requêtes de disponibilité existantes** pour intégrer la composition (couvert par AC-24/25/26).
5. **Trace PaperTrail de la migration** attribuée à un acteur système ? — **VERROUILLÉ : OUI**, whodunnit `"system:migration"`.
6. **`payments through: :stays` dérivé en lecture** (pas de FK `payment.stay_id`, schéma `payments` intact, `Payment.booking_id` reste NOT NULL) ? — **VERROUILLÉ : OUI** (dérivation lecture via booking).
7. **`Customer.notes` visibilité = Pôle Accueil + collectif uniquement** (jamais client/API publique) ? — **VERROUILLÉ : OUI** (interne strict).
8. **`Customer.language` : défaut `fr`, renseigné explicitement plus tard** (pas de détection auto en tranche 1) ? — **VERROUILLÉ : OUI**.

---
*Fin du PRD tranche 1. Le Constructeur, la Directrice Artistique, le Vérificateur et la Plume lisent ce fichier. Les 8 décisions §11 sont verrouillées — build autorisé.*
