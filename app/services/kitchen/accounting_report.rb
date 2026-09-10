module Kitchen
  # Ce que la cuisine a coûté et encaissé sur une période, lu au GRAND LIVRE
  # (epic #269, phase 2).
  #
  # Deux lectures et une seule source. Les DÉPENSES sont les mouvements
  # débiteurs des comptes de charge désignés par Paramètres > Cuisine : les
  # courses se font par lot, pour plusieurs services à la fois, et le ticket
  # arrive déjà en comptabilité — le coût ne se ressaisit nulle part ailleurs.
  # L'ENCAISSÉ est le solde créditeur du compte de recette de la catégorie
  # `meals`, celui que `RevenueMapping` désigne ; il n'est jamais codé en dur,
  # parce qu'un reporting qui invente son périmètre ment.
  #
  # L'encaissé ne vaut PAS le facturé (`Reports::KitchenRevenue`) : un acompte
  # rentre avant la prestation, un solde après. La page affiche les deux et
  # explique l'écart plutôt que de choisir pour le lecteur.
  #
  # Aucun réglage de comptes = aucune dépense, jamais « tous les comptes ».
  # `configured?` permet à la page de le dire au lieu d'afficher un 0 € qui
  # ressemble à une cuisine sans dépenses.
  class AccountingReport
    # La catégorie de `RevenueMapping` qui porte toute la cuisine : repas,
    # buffets et apéros y sont rangés ensemble par `PricingModel#meal_lines`.
    REVENUE_CATEGORY = "meals".freeze

    attr_reader :from, :to

    def initialize(from:, to:)
      @from = from
      @to   = to
    end

    # Les comptes de charge du périmètre, dans l'ordre du plan comptable.
    def expense_accounts = @expense_accounts ||= Kitchen::Config.expense_accounts

    def configured? = expense_accounts.any?

    # Le détail des dépenses de la période, dans l'ordre du grand livre.
    def expense_lines
      @expense_lines ||= configured? ? ledger_lines(expense_accounts.map(&:id)) : []
    end

    # Une charge augmente au débit : c'est `débit - crédit` qui donne la
    # dépense, et une note de crédit fournisseur la diminue d'elle-même.
    def expenses_cents = @expenses_cents ||= expense_lines.sum(&:signed_cents)

    def revenue_account
      return @revenue_account if defined?(@revenue_account)

      @revenue_account = RevenueMapping.find_by(category: REVENUE_CATEGORY)&.general_account
    end

    def revenue_account? = revenue_account.present?

    # Un produit augmente au crédit : `crédit - débit`, sens inverse d'une
    # charge. Sans compte de recette configuré, l'encaissé vaut zéro et la page
    # le signale — elle ne devine pas un compte à sa place.
    def collected_cents
      return 0 if revenue_account.blank?

      @collected_cents ||= begin
        scope = period_lines.where(general_account_id: revenue_account.id)
        scope.sum(:credit_cents) - scope.sum(:debit_cents)
      end
    end

    def any? = expense_lines.any?

    private

    def period_lines
      JournalLine.joins(:journal_entry, :general_account)
                 .where(journal_entries: { entry_date: @from..@to })
    end

    def ledger_lines(account_ids)
      period_lines
        .where(general_account_id: account_ids)
        .preload(:general_account, :third_party, journal_entry: [:fiscal_year, :legal_entity])
        .order("journal_entries.entry_date", "journal_entries.id", "journal_lines.id")
        .to_a
    end
  end
end
