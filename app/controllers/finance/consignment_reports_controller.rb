module Finance
  # Comptabilité > Dépôt-vente (epic #248, phase 2).
  #
  # Le tableau de bord du mois : qui a été sollicité, qui a déclaré, qui reste
  # muet. C'est la question que l'administration se pose le 5 du mois, et
  # jusqu'ici elle n'avait qu'un fil d'emails pour y répondre.
  #
  # La vérification et le règlement arrivent en phase 3 : ici on lit, et on
  # relance.
  class ConsignmentReportsController < Finance::AccountingBaseController
    before_action :get_report, only: %i[resend]

    breadcrumb "Dépôt-vente", :finance_consignment_reports_path, match: :exact

    def index
      @month = parsed_month
      @reports = ConsignmentReport.for_month(@month)
                                  .includes(:consignor, :consignment_report_lines)
                                  .joins(:consignor).merge(Consignor.ordered)
      # Les artisans dont le contrat court ce mois-là et qui n'ont pas encore de
      # relevé : sans eux, l'écran dirait « tout le monde a déclaré » alors que
      # le rake n'a simplement pas été lancé.
      @missing = Consignor.actives.ordered.select { |c| c.running_on?(@month.end_of_month) } -
                 @reports.map(&:consignor)
    end

    # Relance manuelle — le rake est mensuel, mais un artisan perd son mail.
    def resend
      if @report.consignor.email.blank?
        redirect_to finance_consignment_reports_path(month: @report.period_month.strftime("%Y-%m")),
                    alert: "#{@report.consignor.name} n'a pas d'adresse email — le lien est à donner à la main."
        return
      end

      ConsignmentMailer.monthly_request(@report).deliver_later
      @report.update_column(:requested_at, Time.current)

      redirect_to finance_consignment_reports_path(month: @report.period_month.strftime("%Y-%m")),
                  notice: "Demande renvoyée à #{@report.consignor.email}."
    end

    private

    def get_report
      @report = ConsignmentReport.find(params[:id])
    end

    def parsed_month(raw = params[:month])
      raw.present? ? Date.parse(raw.length == 7 ? "#{raw}-01" : raw).beginning_of_month : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def accounting_secondary = "consignment_reports"
  end
end
