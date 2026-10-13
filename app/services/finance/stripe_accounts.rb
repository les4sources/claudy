module Finance
  # Comptabilité > Stripe (epic #250, phase 2) : où en est chaque compte
  # Stripe, et où va chaque catégorie de ventes.
  #
  # Sorti du contrôleur le 2026-10-13 pour que le connecteur Claude lise et
  # change la même chose que l'écran, avec le même garde-fou sur le mode.
  class StripeAccounts
    class ModeRefused < StandardError; end

    def blocks
      CashAccount.stripe.ordered.includes(:legal_entity).map { |account| block_for(account) }
    end

    # Changer de mode est une décision, pas un réglage : elle change la façon
    # dont TOUT ce compte entre en comptabilité. Repasser de `ledger` à
    # `per_payout` est refusé dès qu'une transaction `ledger` existe — les
    # lignes déjà entrées au journal deviendraient orphelines de leur mode.
    def change_mode!(account, mode)
      mode = mode.to_s
      raise ModeRefused, "Mode inconnu." unless CashAccount::STRIPE_MODES.include?(mode)

      if mode == "per_payout" && ledger_transactions?(account)
        raise ModeRefused, "Ce compte a déjà des transactions importées en mode grand livre — " \
                           "revenir au mode par versement laisserait ces lignes sans mode."
      end

      account.update!(stripe_mode: mode)
      account
    end

    def ledger_transactions?(account)
      StripeBalanceTransaction.where(cash_account_id: account.id).exists?
    end

    def block_for(account)
      key = account.stripe_account_key
      payouts = key.present? ? StripePayout.for_account(key) : StripePayout.none
      transactions = key.present? ? StripeBalanceTransaction.for_account(key) : StripeBalanceTransaction.none

      {
        account: account,
        payouts_count: payouts.count,
        transactions_count: transactions.count,
        last_import_at: [payouts.maximum(:created_at), transactions.maximum(:created_at)].compact.max,
        pending_count: CashEntry.pending.where(cash_account_id: account.id).count,
        mappings: account.ledger? ? StripeCategoryMapping.for_account(key).ordered.includes(:general_account, :team, :legal_entity).to_a : [],
        uncovered: account.ledger? ? uncovered_categories(key, transactions) : []
      }
    end

    private

    # Les catégories RENCONTRÉES dans les transactions qu'aucune correspondance
    # ne couvre : c'est ce qui laisse une ligne en attente sur « À affecter ».
    # `nil` (« sans catégorie ») en fait partie — c'est une catégorie comme une
    # autre, pas une absence à ignorer.
    def uncovered_categories(key, transactions)
      rencontrees = transactions.revenue.distinct.pluck(:category).map { |c| c.to_s.strip.presence }.uniq
      couvertes = StripeCategoryMapping.for_account(key).pluck(:category).map { |c| c.to_s.strip.presence }

      (rencontrees - couvertes).map do |category|
        { category: category,
          label: category.presence || StripeCategoryMapping::NO_CATEGORY_LABEL,
          count: transactions.revenue.where(category: category).count,
          gross_cents: transactions.revenue.where(category: category).sum(:gross_cents) }
      end.sort_by { |row| row[:label] }
    end
  end
end
