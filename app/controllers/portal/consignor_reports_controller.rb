module Portal
  # « Encoder une feuille » dans l'espace artisan (epic #359, phase 2, décision 8).
  #
  # L'artisan passe sur le lieu, prend sa feuille pleine et encode ses ventes au
  # téléphone. Le relevé du mois naît à la première sauvegarde, directement
  # `declared` : ici personne ne l'a « demandé ». Une feuille à cheval sur deux
  # mois va au mois où elle est encodée (décision 10) — on ne crée donc un
  # relevé que pour le mois en cours ; les mois passés ne s'ouvrent que s'ils
  # ont déjà un relevé.
  #
  # Plusieurs feuilles par mois : on revient, on ajoute des lignes, on
  # enregistre à nouveau. Modifiable tant que l'administration n'a pas vérifié.
  class ConsignorReportsController < Portal::BaseController
    include ConsignmentReportForm

    before_action :require_portal_consignor
    before_action :get_report

    def show
      render :verified unless @report.editable_by_consignor?
    end

    def update
      return render(:verified, status: :unprocessable_entity) unless @report.editable_by_consignor?

      attrs = consignment_report_params(:sheet_numbers)
      # Les photos s'AJOUTENT : l'artisan encode plusieurs feuilles dans le mois,
      # la photo de la deuxième ne doit pas effacer celle de la première.
      photos = Array(attrs.delete(:photos)).compact_blank
      @report.assign_attributes(attrs)

      if @report.new_record? && @report.consignment_report_lines.none? { |line| !line.marked_for_destruction? }
        flash.now[:alert] = "Ajoutez au moins une vente avant d'enregistrer."
        return render :show, status: :unprocessable_entity
      end

      @report.status = "declared"
      @report.declared_at = Time.current

      if @report.save
        @report.photos.attach(photos) if photos.any?
        redirect_to portal_consignor_report_path(period: params[:period]),
                    notice: "C'est enregistré — vos ventes de #{@report.period_label} sont à jour."
      else
        flash.now[:alert] = @report.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    private

    def get_report
      @consignor = current_portal_consignor
      period = parse_period(params[:period])
      @report = @consignor.consignment_reports.for_month(period).first
      if @report.nil?
        raise ActiveRecord::RecordNotFound unless period == Date.current.beginning_of_month

        @report = @consignor.consignment_reports.new(period_month: period, status: "declared")
      end
      @products = consignment_products_for(@consignor, @report)
    end

    def parse_period(value)
      Date.strptime(value.to_s, "%Y-%m").beginning_of_month
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end
  end
end
