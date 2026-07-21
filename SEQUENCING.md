# Claudy — Séquençage d'exécution (vivant)

> Dérivé de `ISA.md` (Features `StayComposite`/`BookingFlow`/`Activities` + Decisions). **Source de vérité de l'avancement du chantier séjour-composite et de sa suite.**
> Mis à jour : 2026-07-20 (création du fichier — statut consolidé après merge de TOUT le chantier séjour). Statut global : **le pivot Stay-first est TERMINÉ et en prod** — epics #26 (Payment Stay-first) ✅, #55 (activités) ✅, #66 (séjour composable) ✅, #81 (séjour = point d'entrée unique, 9 phases) ✅, #94/#99 (vetos en nuits, retrait édition legacy) ✅, funnel public réparé et enrichi (#104→#107) ✅, calendrier un-bloc-par-séjour (#108) ✅, espaces composés corrigés + migration (#109) ✅. Backfill prod : 0 orphelin (817 bookings, 579 space_bookings rattachés). Suite : **826 ex / 0 failure**. Déploiement Hatchbox fiabilisé (un seul restart — « Deploy on push » activable).

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
- [ ] **B.3 Arbitrages données** *(Michael)* — séjour #1384 (total 265 € ≠ parts 285,25 € — antérieur, refusé par le garde-fou de conversion) ; séjour Semisto aux dates inversées 2027→2026 ; trop-perçu 180 € (reste dû négatif, remboursement à traiter).

## Volet C — Lot du 20-21/07 (LIVRÉ, mergé sur main)

Épuisé en une soirée, tout vérifié (Forge + navigateur + suite complète à chaque merge) :
fusion depuis la fiche client (retour fiche, sessionStorage scopé) · notes séjour (lecture modale, édition, consolidation à la fusion avec provenance) · modale de fusion enrichie + notes calendrier masquées en mode fusion + aperçu espaces agrégé « (3 j) » · suppression client gardée + liste clients (tri séjours, filtres, 100/p) + fiche client (total + icônes) + TVA orga + fix notes · menu « Séjours » + table /stays (encaissé/reste dû) + fiche séjour pleine page (carte blanche) · double-clic statuts · calendrier : un bloc/séjour, 💤 nuitées, « + » unique, mois sans année, chips ⛺️/🚐 courtes, cycles hors Accueil, section veilleur (check-out enfin visibles, bandeaux colorés) · activités : calendrier mensuel interactif (fiche + global), bloc Réservations, « Expériences » en tête des paramètres, durée courte + créneaux à venir · funnel réparé (paiement Stripe #104, page Checkout détaillée #105, 2 emails #106, drawer devis #107) · **camping/van PAR NUIT** (plages contiguës, grille admin, devis exact largest-remainder, durcissements Forge) + grilles qui suivent les dates + devis live d'édition réparé · **terrasse 2,50 €/pers/jour** (fieldset admin, chip 🪑, jamais au public) · équipe (rôles activables, statut, blocage connexion inactifs, accès restreint porteurs) · fourre-tout OTA Airbnb/Booking (anti-fuite) · Laurier liée (+454 résas) · formule repas fantôme retirée · « Formule complète » n'existe plus · conversions Parking→Van et Bois/Pâtures→tentes · facturation espaces → Payments (162+30 localement).

## Volet D — En cours / cette nuit

- [x] **D.1 « Les 2 salles »** — remise duo au devis (funnel + admin), conversion appliquée en local, espace soft-deleté. PR #132.
- [x] **D.2 Nuit du 21/07 (agent nocturne)** — LIVRÉ et mergé le 21/07 matin (main `c964dcb`, 1086 ex / 0 failure) : #124 Tarifs (PR #134) · #127 Coworking Phase 1 (PR #135, conflit #124 résolu — packs raccordés à la façade `Pricing::Rates`, + 4 clés `coworking.pack_*` ajoutées au seed) · #128 Portail OTP + Mes séjours (PR #136) · #133 Modification de séjour client (PR #137). #129/#130 labellisées `agent:ready` pour la nuit suivante.
- [ ] **D.3 Validations à l'œil (issues des PR nocturnes)** — écrans Paramètres > Coworking + bloc calendrier 💻 (PR #135, zéro capture) · les 3 écrans du portail dont « Mes séjours » (PR #136) · formulaire client de modification (grille nuit par nuit préremplie) + diff admin sur un vrai cas (PR #137). À trancher : portail trilingue ? rate-limit sur POST /portail/code ? repas modifiables par le client ?

## Horizon (ISA, non séquencé)

Reporting 7 domaines · BudgetTracking par pôle · BarAndGrocery (kiosk + offline) · Bakery (absorption Tranches de Vie) · GuestMobileApp · PublicApi site · B2bCrm/Faq/AutoAcknowledgement/PostStayNps · funnel B2B `/sejour-entreprise`. → voir `ISA.md` Features pour le détail ; à séquencer ici quand un bloc se lance.
