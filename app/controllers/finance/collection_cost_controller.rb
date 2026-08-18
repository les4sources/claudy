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

      payouts = StripePayout.where(arrival_date: @from..@to).includes(:stripe_balance_transactions)
      @rows = payouts.group_by(&:account_key).map do |account_key, groupe|
        brut = groupe.sum(&:gross_cents)
        frais = groupe.sum(&:fees_cents)

        { label: StripeService.label_for(account_key), payouts: groupe.size,
          gross_cents: brut, fees_cents: frais, net_cents: groupe.sum(&:amount_cents),
          rate: brut.zero? ? nil : (frais.to_f / brut * 100).round(2) }
      end.sort_by { |row| row[:label] }

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

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
