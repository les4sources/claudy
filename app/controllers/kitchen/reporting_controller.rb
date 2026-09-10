module Kitchen
  # Reporting de la cuisine (epic #269, phase 2) : sur une période, ce que la
  # cuisine a facturé, ce qu'elle a encaissé, et ce qu'elle a coûté.
  #
  # La page vit SOUS Cuisine et non sous Reporting : c'est Malau qui la lit, au
  # même endroit que ses services. L'ancienne adresse `/reports/kitchen` y
  # redirige, période comprise.
  #
  # La période par défaut est l'ANNÉE en cours : la rentabilité de la cuisine se
  # lit sur la durée, jamais sur un mois isolé où un lot de courses tombe d'un
  # côté et les repas qu'il a servis de l'autre.
  class ReportingController < BaseController
    breadcrumb "Cuisine", :kitchen_orders_path, match: :exact
    breadcrumb "Reporting", :kitchen_reporting_path, match: :exact

    def show
      set_period
      @revenue = Reports::KitchenRevenue.new(from: @from, to: @to)
      @accounting = Kitchen::AccountingReport.new(from: @from, to: @to)

      respond_to do |format|
        format.html
        format.csv do
          send_data Reports::KitchenCsv.new(@revenue).to_csv,
                    filename: "cuisine-#{@from.iso8601}-#{@to.iso8601}.csv",
                    type: "text/csv; charset=utf-8"
        end
      end
    end

    # Le second export : le détail comptable des dépenses de la période, celui
    # qui répond « d'où vient ce total » sans rouvrir le grand livre.
    def expenses
      set_period
      report = Kitchen::AccountingReport.new(from: @from, to: @to)

      send_data Kitchen::ExpensesCsv.new(report).to_csv,
                filename: "cuisine-depenses-#{@from.iso8601}-#{@to.iso8601}.csv",
                type: "text/csv; charset=utf-8"
    end

    private

    # Une plage à l'envers est retournée plutôt que refusée : c'est une faute de
    # frappe, pas une intention.
    def set_period
      @from = parse_date(params[:from], Date.current.beginning_of_year)
      @to   = parse_date(params[:to], Date.current.end_of_year)
      @to, @from = @from, @to if @to < @from
    end

    def parse_date(value, fallback)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      fallback
    end

    def set_presenters
      @home_view = true
    end
  end
end
