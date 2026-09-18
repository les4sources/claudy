# « Régler l'événement » (epic #245, phase 3).
#
# Un seul geste, irréversible dans le sens où il fige le partage et passe
# l'écriture. Il n'y a pas de « dé-régler » : une correction est une
# contre-passation, pas un retour en arrière silencieux.
class EventSettlementsController < BaseController
  before_action :set_event

  def create
    service = Events::Settle.new(event: @event, whodunnit: current_user&.email)

    if service.run
      redirect_to event_path(@event, tab: "comptabilite"),
                  notice: "Événement réglé : les parts sont figées et apparaissent dans « À payer »."
    else
      redirect_to event_path(@event, tab: "comptabilite"),
                  alert: service.error_message(default: "Règlement impossible.")
    end
  end

  private

  def set_event
    @event = Event.find(params[:event_id])
  end

  def set_presenters
    @home_view = true
  end
end
