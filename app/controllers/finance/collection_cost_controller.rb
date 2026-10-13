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

      # Le calcul vit dans `Finance::CollectionCost` : le connecteur Claude lit
      # le même chiffre que cet écran.
      cout = Finance::CollectionCost.new(from: @from, to: @to)
      @rows = cout.rows
      @total_gross_cents = cout.total_gross_cents
      @total_fees_cents = cout.total_fees_cents
      @global_rate = cout.global_rate
      @transfer_cents = cout.transfer_cents
      @fee_months = cout.fee_months
    end

    private

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
