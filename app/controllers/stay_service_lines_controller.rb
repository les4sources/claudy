# Services annexes d'un séjour (Michael, 2026-10-23), depuis la fiche séjour :
# ajouter une ligne (libellé + montant, préremplie depuis un service du
# catalogue) ou la retirer. Le bloc vit dans la colonne de droite (frame
# `stay_<id>_extras`), les montants à gauche (frame `stay_<id>_payments`) : la
# réponse Turbo Stream remplace les deux, comme pour la Pizza Party.
class StayServiceLinesController < BaseController
  before_action :set_stay

  def create
    service = Stays::AddServiceLine.new(stay: @stay)
    attrs = params.fetch(:stay_service_line, {})
    catalogue = Service.find_by(id: attrs[:service_id]) if attrs[:service_id].present?

    amount_cents = Stays::AddServiceLine.cents_from(attrs[:amount])

    if service.run(label: attrs[:label], amount_cents: amount_cents, service: catalogue)
      respond_with_panels(notice: "Service « #{service.line.label} » ajouté au séjour.")
    else
      respond_with_panels(alert: service.error_message(default: "Ajout impossible."))
    end
  rescue ServiceError => e
    respond_with_panels(alert: e.message)
  end

  def destroy
    line = @stay.service_lines.find(params[:id])
    service = Stays::RemoveServiceLine.new(line: line)

    if service.run
      respond_with_panels(notice: "Service « #{line.label} » retiré du séjour.")
    else
      respond_with_panels(alert: service.error_message(default: "Retrait impossible."))
    end
  end

  private

  def set_stay
    @stay = Stay.find(params[:stay_id])
  end

  def respond_with_panels(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        @stay = Stay.find(@stay.id).decorate
        render turbo_stream: [
          turbo_stream.replace("stay_#{@stay.id}_extras") do
            render_to_string(partial: "stays/extras_panel", formats: [:html], locals: { notice: notice, alert: alert })
          end,
          turbo_stream.replace("stay_#{@stay.id}_payments") do
            render_to_string(partial: "stays/payments_panel", formats: [:html])
          end
        ]
      end
      format.html { redirect_to stay_path(@stay), notice: notice, alert: alert }
    end
  end

  # Même menu que la fiche séjour.
  def set_presenters; end
end
