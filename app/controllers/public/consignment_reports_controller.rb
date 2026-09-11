module Public
  # La page de déclaration d'un artisan en dépôt-vente (epic #248, phase 2,
  # décision 3).
  #
  # Aucune session, aucun Devise : le lien du mail doit s'ouvrir sur le téléphone
  # d'un artisan qui n'a pas de compte dans Claudy — et qui n'en aura jamais.
  # Le jeton EST l'authentification.
  #
  # La page est EN FRANÇAIS UNIQUEMENT, libellés en dur — comme les décomptes
  # sourciers. On n'ajoute pas de clés sous `public.*` : la parité NL/EN est
  # gardée par une spec, et cette page s'adresse à quatre artisans du coin.
  class ConsignmentReportsController < Public::BaseController
    before_action :get_report

    def show
      render :verified if @report.verified? || @report.settled?
    end

    def update
      unless @report.editable_by_consignor?
        return render :verified, status: :unprocessable_entity
      end

      if @report.update(report_params.merge(status: "declared", declared_at: Time.current))
        redirect_to public_consignment_report_path(@report.token),
                    notice: "Merci — vos ventes de #{@report.period_label} nous sont bien arrivées."
      else
        flash.now[:alert] = @report.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    private

    def get_report
      @report = ConsignmentReport.find_by(token: params[:token])
      return render :invalid, status: :not_found if @report.nil?

      @consignor = @report.consignor
    end

    def report_params
      params.require(:consignment_report).permit(
        :notes, photos: [],
        consignment_report_lines_attributes: %i[id label quantity unit_price_euros position _destroy]
      ).tap do |permitted|
        lines = permitted[:consignment_report_lines_attributes]
        next if lines.blank?

        lines.each_value do |line|
          euros = line.delete(:unit_price_euros)
          line[:unit_price_cents] = (euros.to_s.tr(",", ".").to_f * 100).round if euros.present?
        end
      end
    end
  end
end
