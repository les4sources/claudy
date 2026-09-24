module Portal
  # L'espace artisan en dépôt-vente (epic #359, décision 8) : son tableau de
  # bord. Le mois en cours, le dernier relevé, ce qui lui reste dû, et les
  # portes vers « Encoder une feuille » et « Mes produits » (phase 2).
  # L'impression de sa feuille arrive en phase 3.
  #
  # Le scope part TOUJOURS de `current_portal_consignor` : aucun identifiant
  # d'artisan ne circule dans l'URL, il n'y a donc rien à forger.
  class ConsignmentsController < Portal::BaseController
    before_action :require_portal_consignor

    def show
      @consignor = current_portal_consignor
      @reports = @consignor.consignment_reports.ordered.includes(:consignment_report_lines).to_a
      @current_period = Date.current.beginning_of_month
      @current_report = @reports.find { |report| report.period_month == @current_period }
      @last_report = @reports.find { |report| report.period_month < @current_period } || @current_report
      # Ce qui reste dû : le net de chaque relevé pas encore réglé. Un relevé
      # encore ouvert compte pour ses totaux vivants, un vérifié pour ses figés.
      @net_due_cents = @reports.reject(&:settled?).sum(&:displayed_net_cents)
      @products_count = @consignor.catalog_items.craft.active.count
    end
  end
end
