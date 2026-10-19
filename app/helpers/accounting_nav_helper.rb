# La sous-navigation Comptabilité (Michael 2026-09-20).
#
# Dix-neuf entrées débordaient sur deux lignes : on ne les lisait plus, on les
# cherchait. Elles se rangent ici par la QUESTION qu'on se pose en les ouvrant,
# pas par le journal comptable auquel elles écrivent — d'où « Reversements »,
# qui réunit notes de frais, porteurs, déposants et partages de revenus : c'est
# quatre fois le même geste, une dette au 440000 qui attend son virement.
#
# Trois entrées restent DIRECTES, celles qu'on ouvre sans y penser : la vue
# d'ensemble, la trésorerie (l'écran le plus fréquenté de la section) et
# l'arrêté du mois. Les quatre autres sont des circuits qu'on ouvre POUR faire
# quelque chose — ils tiennent dans un menu.
#
# Une entrée : [libellé, chemin, contrôleurs qui l'allument]. Les contrôleurs
# sont écrits en toutes lettres plutôt que déduits du chemin : un écran comme
# la caisse en mobilise trois (feuille, motifs, comptages) et doit rester
# allumé sur les trois.
module AccountingNavHelper
  def accounting_nav_direct
    [
      ["Vue d'ensemble", finance_accounting_path,
       %w[finance/accounting finance/treasury finance/general_accounts finance/legal_entities finance/fiscal_years]],
      ["Trésorerie", finance_cash_entries_path, %w[finance/cash_entries finance/cash_reallocations]],
      ["Arrêté du mois", finance_monthly_close_path, %w[finance/monthly_close]],
      ["Échéancier", finance_compliance_deadlines_path, %w[finance/compliance_deadlines finance/compliance_obligations]]
    ]
  end

  # Un groupe : [libellé, identifiant du menu, entrées]. L'identifiant sert au
  # contrôleur Stimulus `dropdown`, qui ouvre le panneau par son `id`.
  def accounting_nav_groups
    [
      ["Banque & caisse", "banque", [
        ["CODA", finance_coda_imports_path, %w[finance/coda_imports]],
        ["Règles d'affectation", finance_allocation_rules_path, %w[finance/allocation_rules]],
        ["Caisse", finance_cash_sheet_path, %w[finance/cash_sheet finance/cash_motifs finance/cash_counts]],
        ["Stripe", finance_stripe_path, %w[finance/stripe finance/stripe_category_mappings]],
        ["Coût d'encaissement", finance_collection_cost_path, %w[finance/collection_cost]]
      ]],
      ["Fournisseurs", "fournisseurs", [
        ["Boite de réception", finance_mail_messages_path, %w[finance/mail_messages]],
        ["Achats", finance_purchase_invoices_path, %w[finance/purchase_invoices]],
        ["À payer", finance_payables_path, %w[finance/payables]],
        ["Dettes et litiges", finance_liabilities_path, %w[finance/liabilities]],
        ["Charges fixes", finance_recurring_expenses_path, %w[finance/recurring_expenses]],
        ["Tiers", finance_third_parties_path, %w[finance/third_parties]]
      ]],
      # Le miroir de « Fournisseurs » (epic #240, phase 6) : le registre des
      # factures qu'on ÉMET. Son propre menu plutôt qu'une entrée glissée chez
      # les fournisseurs — on n'y vient pas pour la même question.
      ["Clients", "clients", [
        ["Ventes", finance_sales_invoices_path, %w[finance/sales_invoices]]
      ]],
      ["Reversements", "reversements", [
        ["Notes de frais", finance_expense_reports_path, %w[finance/expense_reports]],
        ["Porteurs", finance_carrier_statements_path, %w[finance/carrier_statements]],
        ["Dépôt-vente", finance_consignment_reports_path, %w[finance/consignment_reports]],
        ["Partages de revenus", finance_revenue_share_agreements_path,
         %w[finance/revenue_share_agreements finance/revenue_share_statements]]
      ]],
      ["États", "etats", [
        ["Grand livre", finance_ledger_path, %w[finance/ledger]],
        ["Balance", finance_trial_balance_path, %w[finance/trial_balance]],
        ["Analytique", finance_analytic_balance_path, %w[finance/analytic_balance]],
        ["Budget", finance_budget_path, %w[finance/budgets]],
        ["Contrôle croisé", finance_cross_check_path, %w[finance/cross_check]]
      ]]
    ]
  end

  # Le guide (2026-10-17) : à part, au bout de la barre. Ce n'est pas un
  # circuit de travail mais l'endroit où l'on revient quand un mot arrête.
  def accounting_nav_guide = ["Guide", finance_guide_path, %w[finance/guide]]

  # Une ligne sous chaque libellé (2026-10-17) : « CODA » ou « Tiers » ne disent
  # rien à qui démarre. Par libellé plutôt que dans les entrées, pour que leur
  # forme [libellé, chemin, contrôleurs] reste celle que la spec recense.
  NAV_HINTS = {
    "Vue d'ensemble" => "Peut-on dépenser, et ce qui attend",
    "Trésorerie" => "Tous les mouvements d'argent, et la file À affecter",
    "Arrêté du mois" => "Vérifier puis fermer le mois",
    "Échéancier" => "Les dates légales à tenir",
    "CODA" => "Déposer les relevés de la banque",
    "Règles d'affectation" => "Les propositions automatiques d'affectation",
    "Caisse" => "La feuille d'espèces et les comptages",
    "Stripe" => "Les paiements par carte et leurs catégories",
    "Coût d'encaissement" => "Ce que coûtent les commissions Stripe",
    "Boite de réception" => "Les factures reçues par mail, à classer",
    "Achats" => "Les factures des fournisseurs et leur statut",
    "À payer" => "Les virements à faire, par échéance",
    "Dettes et litiges" => "Ce qu'on doit sans facture",
    "Charges fixes" => "Les dépenses qui reviennent, pour prévoir",
    "Tiers" => "Fournisseurs, clients et prêteurs",
    "Ventes" => "Les factures émises et leur paiement",
    "Notes de frais" => "Rembourser ce qu'une personne a avancé",
    "Porteurs" => "Rémunérer les porteurs d'activité",
    "Dépôt-vente" => "Régler les artisans",
    "Partages de revenus" => "Reverser la part d'un hébergement",
    "Grand livre" => "Toutes les écritures d'un compte",
    "Balance" => "Le total de chaque compte",
    "Analytique" => "Ce que chaque pôle rapporte et coûte",
    "Budget" => "Ce qu'on prévoit, pôle par pôle et compte par compte",
    "Contrôle croisé" => "L'argent encaissé face aux séjours facturés",
    "Guide" => "Le mode d'emploi et le lexique"
  }.freeze

  def accounting_nav_hint(label) = NAV_HINTS[label]

  def accounting_nav_current?(controllers) = controllers.include?(controller_path)

  # Un menu s'allume quand on est SUR une de ses entrées : sans ça, ouvrir le
  # grand livre effacerait toute trace de « vous êtes ici » dans la barre.
  def accounting_nav_group_current?(entries) = entries.any? { |(_, _, ctrls)| accounting_nav_current?(ctrls) }
end
