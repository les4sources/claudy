module Finance
  # La balance des tiers (Michael, 2026-10-30) : à une date, le solde de chaque
  # fournisseur ou de chaque client, par structure. Un clic sur un compte
  # ouvre son grand livre, filtré sur ce tiers.
  class ThirdPartyBalanceController < Finance::AccountingBaseController
    breadcrumb "Balance tiers", :finance_third_party_balance_path, match: :exact

    def index
      load_entity_filter
      @as_of = parsed_date(params[:as_of]) || Date.current
      @show_settled = params[:settled] == "1"
      @balance = Accounting::ThirdPartyBalance.new(
        side: params[:side], as_of: @as_of, entities: @entity ? [@entity] : @entities.to_a
      )
      @rows = @show_settled ? @balance.rows : @balance.open_rows
    end

    private

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end
  end
end
