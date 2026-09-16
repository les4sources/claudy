module Finance
  # Ce que coûte le fait d'être payé (issue #187).
  #
  # Le chiffre que personne ne connaît aujourd'hui : la commission Stripe, en
  # euros et en pourcentage du canal. C'est lui qui justifie de mettre le
  # virement en avant sur les emails de solde — un virement ne coûte pas de
  # commission, et sur des séjours à quatre chiffres l'écart est réel.
  class CollectionCostController < Finance::AccountingBaseController
    breadcrumb "Coût d'encaissement", :finance_collection_cost_path, match: :exact

    def index
      @from = parsed_date(params[:from]) || Date.current.beginning_of_year
      @to = parsed_date(params[:to]) || Date.current.end_of_year

      # DEUX BASES DE CALCUL, et le tableau dit laquelle (epic #250, phase 2).
      # En mode `per_payout`, le coût se lit par VERSEMENT : chaque versement
      # porte ses transactions. En mode `ledger`, les versements n'ont pas de
      # composantes — les transactions du solde arrivent indépendamment d'eux :
      # le coût se lit alors par TRANSACTION, sur `occurred_at`. Lire un compte
      # `ledger` par versement donnerait zéro, ce qui n'est pas « rien à payer »
      # mais « on ne regarde pas au bon endroit ».
      @rows = (per_payout_rows + ledger_rows).sort_by { |row| row[:label] }

      @total_gross_cents = @rows.sum { |row| row[:gross_cents] }
      @total_fees_cents = @rows.sum { |row| row[:fees_cents] }
      @global_rate = @total_gross_cents.zero? ? nil : (@total_fees_cents.to_f / @total_gross_cents * 100).round(2)

      # Le virement, lui, ne coûte rien. Le montant encaissé hors Stripe sur la
      # période donne l'ordre de grandeur de ce qu'on économise déjà.
      @transfer_cents = CashEntry.joins(:cash_account)
                                 .where(cash_accounts: { kind: "bank" })
                                 .where(entry_date: @from..@to)
                                 .where("cash_entries.amount_cents > 0")
                                 .sum(:amount_cents)
    end

    private

    # Les comptes Stripe en mode grand livre : leur clé, pour les écarter du
    # calcul par versement.
    def ledger_keys
      @ledger_keys ||= CashAccount.stripe_ledger.pluck(:stripe_account_key).compact
    end

    def per_payout_rows
      payouts = StripePayout.where(arrival_date: @from..@to)
                            .where.not(account_key: ledger_keys)
                            .includes(:stripe_balance_transactions)

      payouts.group_by(&:account_key).map do |account_key, groupe|
        brut = groupe.sum(&:gross_cents)
        frais = groupe.sum(&:fees_cents)

        { label: StripeService.label_for(account_key), basis: :payout, payouts: groupe.size,
          gross_cents: brut, fees_cents: frais, net_cents: groupe.sum(&:amount_cents),
          rate: rate(frais, brut) }
      end
    end

    def ledger_rows
      ledger_keys.filter_map do |account_key|
        scope = StripeBalanceTransaction.for_account(account_key).where(occurred_at: @from.beginning_of_day..@to.end_of_day)
        next if scope.empty?

        brut = scope.revenue.sum(:gross_cents)
        # Les frais sont NÉGATIFS au grand livre : on les lit en valeur absolue,
        # comme dans le calcul par versement.
        frais = scope.revenue.sum(:fee_cents).abs + scope.costs.sum(:net_cents).abs

        { label: StripeService.label_for(account_key), basis: :transaction,
          payouts: StripePayout.for_account(account_key).where(arrival_date: @from..@to).count,
          gross_cents: brut, fees_cents: frais, net_cents: scope.revenue.sum(:net_cents),
          rate: rate(frais, brut) }
      end
    end

    def rate(frais, brut)
      brut.zero? ? nil : (frais.to_f / brut * 100).round(2)
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
