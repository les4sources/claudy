# Claudy — Séquençage d'exécution (vivant)

> Dérivé de `ISA.md` (Features `StayComposite`/`BookingFlow`/`Activities` + Decisions). **Source de vérité de l'avancement du chantier séjour-composite et de sa suite.**
> Mis à jour : 2026-09-07 (Volet E — Administratif & Finances) · 2026-07-20 (création du fichier — statut consolidé après merge de TOUT le chantier séjour). Statut global : **le pivot Stay-first est TERMINÉ et en prod** — epics #26 (Payment Stay-first) ✅, #55 (activités) ✅, #66 (séjour composable) ✅, #81 (séjour = point d'entrée unique, 9 phases) ✅, #94/#99 (vetos en nuits, retrait édition legacy) ✅, funnel public réparé et enrichi (#104→#107) ✅, calendrier un-bloc-par-séjour (#108) ✅, espaces composés corrigés + migration (#109) ✅. Backfill prod : 0 orphelin (817 bookings, 579 space_bookings rattachés). Suite : **826 ex / 0 failure**. Déploiement Hatchbox fiabilisé (un seul restart — « Deploy on push » activable).

## Règles d'exécution (non négociables)

1. **Gate de livraison** : une tranche n'est « faite » qu'avec (a) suite RSpec complète verte, (b) revue **Forge** (GPT-5.4) sur le diff de branche, (c) vérification **agent-browser** du parcours réel (desktop + mobile pour l'UI), (d) PR mergée. « curl 200 » n'est pas une vérification.
2. **PR = review Michael** sauf mandat explicite de merge direct. Piles empilées : recibler la PR suivante sur main AVANT de merger/supprimer une branche de base.
3. **Déploiement Hatchbox manuel** (un seul restart suffit depuis le drop-in systemd 2026-07-20) tant que « Deploy on push » n'est pas activé. Ne jamais supposer que merge = déployé.
4. **Agents nocturnes** : une issue n'est traitée la nuit que complète ET labellisée `agent:ready` (cf. `~/code/nightly/README.md`). Jamais d'issue « titre seul ».
5. **Re-plan à chaque évolution** : toute décision produit → ce fichier + `ISA.md` (Decisions/Changelog) avant de continuer.
6. Légende : `[ ]` todo · `[~]` en cours · `[x]` fait+vérifié.
7. **Agents worktree** : après toute reprise (SendMessage), vérifier que le diff `main...branche` est non vide avant revue/PR (leçon 2026-07-20).

---

## Volet A — Pivot séjour-composite (TERMINÉ)

- [x] **A.1 Tranche 1** (2026-05-30) — `Customer` + `Stay` + migration legacy idempotente + première suite de tests + re-ventilation interactive.
- [x] **A.2 Epic #26** (13-16/07) — Payment Stay-first, 4 phases : page publique `/sejour/:token`, Stripe stay-first, canal admin/OTA sur Stay, verrouillage `verify_stay_links` 601/601.
- [x] **A.3 Epic #55** (16/07) — activités intégrées au séjour, validation porteur double canal, système acompte/solde exigible.
- [x] **A.4 Epic #66** (18/07) — CRUD Stay admin composable (espaces, camping, van, repas), calendrier groupé/coloré par séjour + modale, Builder crée les `Reservation` de chambres (source du veto).
- [x] **A.5 Epic #81** (19/07) — séjour = point d'entrée UNIQUE (admin + funnel) : fusion de séjours (`MergeService` + mode fusion calendrier, sélection inter-mois), prix imposé, chambres seules, duplication, `DraftReconstructor`, retrait de la création directe. Pile #90→#101 mergée.
- [x] **A.6 Exploitation** (20/07) — déployé, backfill 0 orphelin, hotfix calendrier public #100, #99 (édition legacy retirée + `Stays::DestroyService`), #94 (vetos en nuits `[arrivée, départ)`, dos-à-dos OK).
- [x] **A.7 Funnel public fiabilisé** (20/07) — #104 le clic paiement aboutit (form `data-turbo=false`, fallback stay-first) · #105 page Stripe lisible (dates, acompte vs total, composition, email prérempli) · #106 flux 2 emails (demande + acompte reçu au webhook) · #107 devis en drawer (barre sticky + slide-over/bottom-sheet).
- [x] **A.8 Lisibilité calendrier** (20/07) — #108 un bloc par séjour et par jour (presenter `Calendar::DayStayBlocks`) · #109 espaces composés : durées canoniques + dates réelles + migration de données.

## Volet B — Exploitation & assainissement (ACTIF)

- [ ] **B.1 Assainissement historique 2023→aujourd'hui** *(Michael, avec la fusion — calendrier OU fiche client)* — notes consolidées automatiquement à la fusion, aperçu agrégé. Signal de fin : plus de doublons ni d'orphelins 2023→2026.
- [~] **B.2 Déploiement du lot du 20-21/07** *(Michael)* — main déployable en continu (966 specs vertes). Post-deploy, rake en dry-run puis APPLY, dans l'ordre : `bookings:convert_parking_to_van` (16) · `bookings:convert_tent_spaces_to_camping` (13 convertis dont 7 à personnes arrondies ; #605 refusé — séjour #1384 pré-incohérent, correction manuelle) · `customers:ensure_ota_catch_alls` · `rooms:link_laurier` (~454) · `space_bookings:billing_to_payments` (166+30 ; poser d'abord un moyen de paiement sur SpaceBookings #82 et #686) · `spaces:convert_deux_salles` (64 bookings → paires, 7 collisions historiques acceptées, l'espace est soft-deleté en fin) · `stays:recompute_payment_statuses` (11 statuts périmés en local).
- [x] **B.2bis Rake prod exécutées** (21/07, Michael) — toutes appliquées et vérifiées : vans 17, tentes 14, catch-alls 2, rates 47 (4 coworking, 0 pizza), 2 salles soft-deleted, 190 payments espaces, dry-runs de contrôle à zéro. Skips assumés : 19 soldes dus sur séjours morts, 360 sans signal monétaire, 7 cautions listées non transformées.
- [x] **B.3 Arbitrages données** — #1384 corrigé (total → 285,25 €) ; #1414 Semisto dates corrigées (Michael) ; #966 Guillaume annulé (Michael) ; #1418 = séjour Thomas Melchers (40 ans de Camille), total corrigé à 180 € — ce n'était PAS un trop-perçu.

## Volet C — Lot du 20-21/07 (LIVRÉ, mergé sur main)

Épuisé en une soirée, tout vérifié (Forge + navigateur + suite complète à chaque merge) :
fusion depuis la fiche client (retour fiche, sessionStorage scopé) · notes séjour (lecture modale, édition, consolidation à la fusion avec provenance) · modale de fusion enrichie + notes calendrier masquées en mode fusion + aperçu espaces agrégé « (3 j) » · suppression client gardée + liste clients (tri séjours, filtres, 100/p) + fiche client (total + icônes) + TVA orga + fix notes · menu « Séjours » + table /stays (encaissé/reste dû) + fiche séjour pleine page (carte blanche) · double-clic statuts · calendrier : un bloc/séjour, 💤 nuitées, « + » unique, mois sans année, chips ⛺️/🚐 courtes, cycles hors Accueil, section veilleur (check-out enfin visibles, bandeaux colorés) · activités : calendrier mensuel interactif (fiche + global), bloc Réservations, « Expériences » en tête des paramètres, durée courte + créneaux à venir · funnel réparé (paiement Stripe #104, page Checkout détaillée #105, 2 emails #106, drawer devis #107) · **camping/van PAR NUIT** (plages contiguës, grille admin, devis exact largest-remainder, durcissements Forge) + grilles qui suivent les dates + devis live d'édition réparé · **terrasse 2,50 €/pers/jour** (fieldset admin, chip 🪑, jamais au public) · équipe (rôles activables, statut, blocage connexion inactifs, accès restreint porteurs) · fourre-tout OTA Airbnb/Booking (anti-fuite) · Laurier liée (+454 résas) · formule repas fantôme retirée · « Formule complète » n'existe plus · conversions Parking→Van et Bois/Pâtures→tentes · facturation espaces → Payments (162+30 localement).

## Volet D — En cours / cette nuit

- [x] **D.1 « Les 2 salles »** — remise duo au devis (funnel + admin), conversion appliquée en local, espace soft-deleté. PR #132.
- [x] **D.2 Nuit du 21/07 (agent nocturne)** — LIVRÉ et mergé le 21/07 matin (main `c964dcb`, 1086 ex / 0 failure) : #124 Tarifs (PR #134) · #127 Coworking Phase 1 (PR #135, conflit #124 résolu — packs raccordés à la façade `Pricing::Rates`, + 4 clés `coworking.pack_*` ajoutées au seed) · #128 Portail OTP + Mes séjours (PR #136) · #133 Modification de séjour client (PR #137). #129/#130 labellisées `agent:ready` pour la nuit suivante.
- [x] **D.4 Retours du 21/07 matin** — portail : PRG /portail/verification (fix Turbo) + rate-limit 5 codes/h/email + CSP Vite (port) · Pizza Party retirée du seed (app boulangerie) · modification de séjour : grille préremplie (`lodging_night_ids`) + **PRIX PRÉSERVÉ** (delta = recote proposé − recote actuel appliqué au prix existant, imposé à l'approbation) · **paiements depuis la modale séjour** (ajout, bascule pending↔paid, bandeau « Séjour intégralement payé », `set_payment_status` auto, turbo-frame) — tout vérifié navigateur, main `a2b8d13`, 1096 ex / 0 failure.
- [ ] **D.3 Validations à l'œil (issues des PR nocturnes)** — écrans Paramètres > Coworking + bloc calendrier 💻 (PR #135, zéro capture) · les 3 écrans du portail dont « Mes séjours » (PR #136) · formulaire client de modification (grille nuit par nuit préremplie) + diff admin sur un vrai cas (PR #137). À trancher : portail trilingue ? rate-limit sur POST /portail/code ? repas modifiables par le client ?

## Volet E — Administratif & Finances, lots C et E (CADRÉ le 2026-09-07, agents nocturnes)

Issues rédigées depuis la note vocale « 4S : Admin dans Claudy » (2026-09-07) et le plan `docs/epics/2026-07-27-finances.md` (branche `plan/epic-finances`). Lots A (compte sourcier) et B (partie double, trésorerie, CODA, rapprochement, Stripe multi-comptes) sont livrés ; ce volet couvre ce qui manquait pour que l'administratif tienne dans Claudy. Toutes portent `agent:ready` ; l'agent avance une phase par epic et par nuit. Les huit questions ouvertes du cadrage ont été tranchées par Michael le 2026-09-07 soir (une seule caisse · un compte sourcier par cuisinier, payé par virement · tiny house trimestrielle · dépôt-vente 20 % + virement · pas de self-service des notes de frais pour l'instant · registre des ventes construit · Billit : décision reportée à fin T4 2026, OkiOki a été sollicité pour une API/MCP · 0,47 €/km) ; chaque issue porte son tableau « Décisions prises ».

- [ ] **E.1 Pôles** — #239 : Paramètres > Pôles (CRUD + membres), rassemblements ↔ pôles, page du pôle dans Organisation avec bloc financier, fiche humain. Budget 2027 : hors scope, à brainstormer.
- [ ] **E.2 Factures** — #240 : tiers (écran), factures d'achat (PDF, lignes compte/pôle, statuts `to_process → to_validate → to_pay → paid`, écriture `purchases` à `to_pay`), validation par le pôle par lien signé, file « À payer » + concern `Payable` + rapprochement sur `440000`, justificatif Stripe mensuel, registre des ventes OkiOki (sans écriture — règle B2). Billit : hors epic ; décision reportée à fin T4 2026 (OkiOki sollicité pour une API/MCP).
- [ ] **E.3 Notes de frais et de mission** — #241 : `ExpenseReport` (kind frais/mission), IBAN chiffré sur `humans`, tarif `mileage.per_km` (0,47 €/km, daté), numéro de pièce, écriture, paiement + email. La compta encode seule ; le self-service « Mes notes » est reporté (Michael, 2026-09-07).
- [ ] **E.4 Commentaires & notifications** — #242 : `Comment` polymorphe (Basecamp-style) + `Notification` + cloche ; branché sur rassemblements/séjours d'abord, puis notes de frais et factures.
- [ ] **E.5 Caisse** — #243 : motifs (= affectation), feuille de caisse mensuelle mobile-first, comptage avec écart figé. UNE caisse comptable (plan C1, confirmé le 2026-09-07) ; les retours bar/épicerie sont des recettes.
- [ ] **E.6 Activités : tenue & rémunération des porteurs** — #244 : pôle + tarif `activity.carrier_hourly` (40 €/h, surcharge par activité), `outcome` held/no_show (reprise 2026 en masse), relevé trimestriel par porteur → « À payer ».
- [ ] **E.7 Événements** — #245 : organisateurs (poids), taux `event.organizer_share` (70 %), frais fixes, recettes par allocation `document`, page comptable, règlement → « À payer ».
- [ ] **E.8 Batch cooking** — #246 : portions par ménage (5 €), **un compte sourcier personnel par cuisinier** (enfants inclus, `MemberAccount.for_human!`) crédité de 3,50 €/portion, soldé **par virement** via « À payer » (2 phases).
- [ ] **E.9 Tiny house** — #247 (issue) : `RevenueShareAgreement` 50 %, relevé trimestriel (confirmé ; mensuel possible par réglage), écriture, page à jeton → « À payer ».
- [ ] **E.10 Dépôt-vente** — #248 : artisans (commission 20 % confirmée, mode facture ou virement — les membres aussi par virement), déclaration mensuelle par lien à jeton, vérification, règlement. Compensation sur compte sourcier : hors scope.

Déjà couvert, rien à faire : import CODA (#181), réconciliation ligne par ligne et rapprochement assisté (#179/#183), comptes bancaires + Stripe multi-comptes et coût d'encaissement (#187 — les clés du compte Stripe « tranche_de_vie » restent à renseigner par Michael), arrêté du mois (#189). Dépendance transversale : la file « À payer » (E.2 phase 4) est le point de convergence de E.3, E.6, E.7, E.9 et E.10 — leurs dernières phases l'attendent.

## Horizon (ISA, non séquencé)

Reporting 7 domaines · BudgetTracking par pôle · BarAndGrocery (kiosk + offline) · Bakery (absorption Tranches de Vie) · GuestMobileApp · PublicApi site · B2bCrm/Faq/AutoAcknowledgement/PostStayNps · funnel B2B `/sejour-entreprise`. → voir `ISA.md` Features pour le détail ; à séquencer ici quand un bloc se lance.
