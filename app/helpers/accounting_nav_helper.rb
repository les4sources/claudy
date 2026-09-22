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
       %w[finance/accounting finance/general_accounts finance/legal_entities finance/fiscal_years]],
      ["Trésorerie", finance_cash_entries_path, %w[finance/cash_entries]],
      ["Arrêté du mois", finance_monthly_close_path, %w[finance/monthly_close]]
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
        ["Achats", finance_purchase_invoices_path, %w[finance/purchase_invoices]],
        ["À payer", finance_payables_path, %w[finance/payables]],
        ["Tiers", finance_third_parties_path, %w[finance/third_parties]]
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
        ["Contrôle croisé", finance_cross_check_path, %w[finance/cross_check]]
      ]]
    ]
  end

  def accounting_nav_current?(controllers) = controllers.include?(controller_path)

  # Un menu s'allume quand on est SUR une de ses entrées : sans ça, ouvrir le
  # grand livre effacerait toute trace de « vous êtes ici » dans la barre.
  def accounting_nav_group_current?(entries) = entries.any? { |(_, _, ctrls)| accounting_nav_current?(ctrls) }
end
