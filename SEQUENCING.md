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

- [ ] **B.1 Assainissement historique 2023→aujourd'hui** *(Michael, avec l'outil de fusion)* — remonter les séjours via le mode fusion du calendrier + la re-ventilation, jusqu'à cohérence complète. C'est LA raison d'être de la fusion. Signal de fin : plus de doublons ni d'orphelins visibles sur 2023→2026.
- [ ] **B.2 Activer « Deploy on push »** *(Michael, UI Hatchbox)* — les restarts sont déterministes depuis le drop-in systemd. Après activation : merge sur main = prod.
- [ ] **B.3 Vérif post-deploy du lot du 20/07** *(Michael)* — page Stripe détaillée, les 2 emails, drawer devis, calendrier un-bloc, salle « 22 · journée » sur le séjour test (la migration #109 tourne au deploy).

## Volet C — Dette & suites connues (à séquencer)

- [ ] **C.1 Issue #52 — PaperTrail ne versionne pas les `Payment`** (PK UUID vs `versions.item_id` bigint) — viole P2, découvert à l'epic #26. Candidat agent nocturne (issue à compléter avant `agent:ready`).
- [ ] **C.2 `ExperienceBooking` sans soft-deletion** — la suppression d'un séjour annule ses activités (`cancelled`, #99) mais le modèle n'a pas `has_soft_deletion` : cascade incohérente avec les autres bookables. Follow-up recommandé par la Decision #99.
- [ ] **C.3 Questions produit en attente (PRs mergées)** — #90 : couvrir ou non les SpaceBooking soft-deleted historiques dans le backfill ; #91 : blocs calendrier fusionnés, nom du Booking vs client du séjour (reco : client du séjour).
- [ ] **C.4 Petits restes UX** — devis : agréger les lignes camping (« 2 pers × 2 nuits » au lieu de 2 lignes × 1 nuit) · drawer : piège à focus complet (Tab confiné au dialog) · calendrier : badge court pour « période non précisée » + tooltips sur les codes espaces (TIL/SAU/CUI) · funnel : `min` dynamique du champ départ (AC-D-02, reste de l'epic #27).
- [ ] **C.5 Restes epic #66 « à caler »** — vérifier en prod : capacités globales camping/van par défaut (30 pers / 5 véh.), paramétrage `Space.code` complet (TIL/SAU/CUI).
- [ ] **C.6 Tests Stripe non hermétiques ?** — non observé sur claudy (stub `StripeService.instance`) ; garder l'œil si des clés TEST apparaissent en env local.

## Horizon (ISA, non séquencé)

Reporting 7 domaines · BudgetTracking par pôle · BarAndGrocery (kiosk + offline) · Bakery (absorption Tranches de Vie) · GuestMobileApp · PublicApi site · B2bCrm/Faq/AutoAcknowledgement/PostStayNps · funnel B2B `/sejour-entreprise`. → voir `ISA.md` Features pour le détail ; à séquencer ici quand un bloc se lance.
