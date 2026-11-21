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
      # Nouvelle interface (2026-11-12) : la porte de la Comptabilité est « À
      # faire » ; la vue d'ensemble est partie dans la Situation financière.
      [(respond_to?(:new_interface?) && new_interface? ? "À faire" : "Vue d'ensemble"), finance_accounting_path,
       %w[finance/accounting finance/treasury finance/general_accounts finance/fiscal_years]],
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
        ["Comptes de trésorerie", finance_cash_accounts_path, %w[finance/cash_accounts]],
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
        ["Balance tiers", finance_third_party_balance_path, %w[finance/third_party_balance]],
        ["Analytique", finance_analytic_balance_path, %w[finance/analytic_balance]],
        ["Comptes annuels", finance_annual_accounts_path, %w[finance/annual_accounts]],
        ["Immobilisations", finance_fixed_assets_path, %w[finance/fixed_assets]],
        ["Export comptable", finance_accountant_export_path, %w[finance/accountant_exports]],
        ["Budget", finance_budget_path, %w[finance/budgets]],
        ["Contrôle croisé", finance_cross_check_path, %w[finance/cross_check]]
      ]]
    ]
  end

  # LA BARRE DE LA NOUVELLE INTERFACE (Michael, 2026-11-12) : par files, avec
  # leurs compteurs. Les files qu'on vide chaque semaine sont en entrées
  # directes, un clic ; ce qu'on ouvre une fois par mois tient dans un menu ;
  # les réglages sont au bout, derrière l'engrenage. L'ancienne interface
  # garde `accounting_nav_direct` / `accounting_nav_groups`.
  #
  # Une entrée garde la forme [libellé, chemin, écrans qui l'allument] ; un
  # écran est un `controller_path`, ou `controller_path#action` quand une
  # action est sa propre file (« À affecter » dans le journal de trésorerie).
  def accounting_nav_v2_direct
    [
      ["À faire", finance_accounting_path, %w[finance/accounting]],
      ["Boîte mail", finance_mail_messages_path, %w[finance/mail_messages]],
      ["À affecter", finance_unallocated_cash_entries_path, %w[finance/cash_entries#unallocated]],
      ["Achats", finance_purchase_invoices_path, %w[finance/purchase_invoices]],
      ["À payer", finance_payables_path, %w[finance/payables]],
      ["Ventes", finance_sales_invoices_path, %w[finance/sales_invoices]]
    ]
  end

  def accounting_nav_v2_groups
    [
      ["Reversements", "v2-reversements", [
        ["Notes de frais", finance_expense_reports_path, %w[finance/expense_reports]],
        ["Porteurs", finance_carrier_statements_path, %w[finance/carrier_statements]],
        ["Dépôt-vente", finance_consignment_reports_path, %w[finance/consignment_reports]],
        ["Partages de revenus", finance_revenue_share_agreements_path,
         %w[finance/revenue_share_agreements finance/revenue_share_statements]]
      ]],
      ["Banque", "v2-banque", [
        ["Journal de trésorerie", finance_cash_entries_path, %w[finance/cash_entries finance/cash_reallocations]],
        ["Relevés CODA", finance_coda_imports_path, %w[finance/coda_imports]],
        ["Caisse", finance_cash_sheet_path, %w[finance/cash_sheet finance/cash_counts]],
        ["Stripe", finance_stripe_path, %w[finance/stripe finance/stripe_category_mappings]],
        ["Coût d'encaissement", finance_collection_cost_path, %w[finance/collection_cost]],
        ["Solde et prévisions", finance_treasury_path, %w[finance/treasury]]
      ]],
      ["Livres", "v2-livres", [
        ["Grand livre", finance_ledger_path, %w[finance/ledger]],
        ["Balance", finance_trial_balance_path, %w[finance/trial_balance]],
        ["Balance tiers", finance_third_party_balance_path, %w[finance/third_party_balance]],
        ["Analytique", finance_analytic_balance_path, %w[finance/analytic_balance]],
        ["Budget", finance_budget_path, %w[finance/budgets]],
        ["Immobilisations", finance_fixed_assets_path, %w[finance/fixed_assets]],
        ["Dettes et litiges", finance_liabilities_path, %w[finance/liabilities]]
      ]],
      ["Clôture", "v2-cloture", [
        ["Arrêté du mois", finance_monthly_close_path, %w[finance/monthly_close]],
        ["Échéancier", finance_compliance_deadlines_path, %w[finance/compliance_deadlines finance/compliance_obligations]],
        ["Exercices", finance_fiscal_years_path, %w[finance/fiscal_years]],
        ["Comptes annuels", finance_annual_accounts_path, %w[finance/annual_accounts]],
        ["Export comptable", finance_accountant_export_path, %w[finance/accountant_exports]],
        ["Contrôle croisé", finance_cross_check_path, %w[finance/cross_check]]
      ]],
      # Les réglages : ce qu'on installe une fois et qu'on corrige rarement.
      ["Réglages", "v2-reglages", [
        ["Plan comptable", finance_general_accounts_path, %w[finance/general_accounts]],
        ["Comptes de trésorerie", finance_cash_accounts_path, %w[finance/cash_accounts]],
        ["Tiers", finance_third_parties_path, %w[finance/third_parties]],
        ["Règles d'affectation", finance_allocation_rules_path, %w[finance/allocation_rules]],
        ["Charges fixes", finance_recurring_expenses_path, %w[finance/recurring_expenses]],
        ["Motifs de caisse", finance_cash_motifs_path, %w[finance/cash_motifs]]
      ]]
    ]
  end

  # Les compteurs de la barre : ce qui attend dans chaque file, `nil` quand
  # rien n'attend (pas de « 0 » qui fait du bruit). Un menu porte la somme de
  # ses entrées. Calculés une fois par page.
  def accounting_nav_v2_counts
    @accounting_nav_v2_counts ||= {
      "Boîte mail" => MailMessage.pending.count,
      "À affecter" => CashEntry.pending.count,
      "Achats" => PurchaseInvoice.with_status("to_process").count,
      "À payer" => Finance::PayableQueue.new.rows.size,
      "Notes de frais" => ExpenseReport.with_status("recorded").count,
      "Porteurs" => CarrierStatement.draft.count
    }.transform_values { |n| n.positive? ? n : nil }
  end

  def accounting_nav_v2_count(label) = accounting_nav_v2_counts[label]

  # L'entrée allumée : celle qui nomme l'action exacte l'emporte sur celle qui
  # nomme tout le contrôleur (« À affecter » plutôt que le journal).
  def accounting_nav_v2_current_label
    return @accounting_nav_v2_current_label if defined?(@accounting_nav_v2_current_label)

    entries = accounting_nav_v2_direct + accounting_nav_v2_groups.flat_map(&:last) + [accounting_nav_guide]
    exact = entries.find { |(_, _, ctrls)| ctrls.include?("#{controller_path}##{action_name}") }
    @accounting_nav_v2_current_label = (exact || entries.find { |(_, _, ctrls)| ctrls.include?(controller_path) })&.first
  end

  def accounting_nav_v2_group_count(entries)
    total = entries.sum { |(label, _, _)| accounting_nav_v2_counts[label].to_i }
    total.positive? ? total : nil
  end

  # Le guide (2026-10-17) : à part, au bout de la barre. Ce n'est pas un
  # circuit de travail mais l'endroit où l'on revient quand un mot arrête.
  def accounting_nav_guide = ["Guide", finance_guide_path, %w[finance/guide]]

  # Une ligne sous chaque libellé (2026-10-17) : « CODA » ou « Tiers » ne disent
  # rien à qui démarre. Par libellé plutôt que dans les entrées, pour que leur
  # forme [libellé, chemin, contrôleurs] reste celle que la spec recense.
  NAV_HINTS = {
    "Vue d'ensemble" => "Peut-on dépenser, et ce qui attend",
    "À faire" => "Les files de travail, dans l'ordre du circuit",
    "Trésorerie" => "Tous les mouvements d'argent, et la file À affecter",
    "Arrêté du mois" => "Vérifier puis fermer le mois",
    "Échéancier" => "Les dates légales à tenir",
    "CODA" => "Déposer les relevés de la banque",
    "Comptes de trésorerie" => "Les comptes en banque et leur IBAN",
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
    "Balance tiers" => "Ce qu'on doit à chaque fournisseur, ce que chaque client doit",
    "Analytique" => "Ce que chaque pôle rapporte et coûte",
    "Comptes annuels" => "Bilan et compte de résultats, au format BNB",
    "Immobilisations" => "Les biens durables et leurs amortissements",
    "Export comptable" => "Tout un exercice, en fichiers pour le comptable",
    "Budget" => "Ce qu'on prévoit, pôle par pôle et compte par compte",
    "Contrôle croisé" => "L'argent encaissé face aux séjours facturés",
    "Guide" => "Le mode d'emploi et le lexique",
    "Journal de trésorerie" => "Tous les mouvements de banque, de caisse et de Stripe",
    "Relevés CODA" => "Déposer les relevés de la banque",
    "Solde et prévisions" => "Ce qu'il y a en banque, ce qui va rentrer et sortir",
    "Exercices" => "Ouvrir, clôturer, l'à-nouveau",
    "Plan comptable" => "Les comptes dans lesquels on range chaque montant",
    "Motifs de caisse" => "Les raisons d'une entrée ou d'une sortie d'espèces",
    "Boîte mail" => "Les factures reçues par mail, à classer",
    "À affecter" => "Les mouvements à expliquer, ligne par ligne"
  }.freeze

  def accounting_nav_hint(label) = NAV_HINTS[label]

  def accounting_nav_current?(controllers)
    controllers.include?(controller_path) || controllers.include?("#{controller_path}##{action_name}")
  end

  # Un menu s'allume quand on est SUR une de ses entrées : sans ça, ouvrir le
  # grand livre effacerait toute trace de « vous êtes ici » dans la barre.
  def accounting_nav_group_current?(entries) = entries.any? { |(_, _, ctrls)| accounting_nav_current?(ctrls) }
end
