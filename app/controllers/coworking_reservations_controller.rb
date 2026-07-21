# Pose et annulation des journées de coworking d'un pack (epic #126, Phase 1).
# Réservé à l'équipe : aucune règle d'heure limite ici (Phase 3 côté portail).
class CoworkingReservationsController < BaseController
  before_action :get_pack

  def create
    reservation = @pack.coworking_reservations.new(date: params.dig(:coworking_reservation, :date))

    if reservation.save
      redirect_to coworking_pack_path(@pack),
                  notice: "La journée du #{I18n.l(reservation.date, format: :long)} a été réservée."
    else
      redirect_to coworking_pack_path(@pack),
                  alert: reservation.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    reservation = @pack.coworking_reservations.find(params[:id])
    reservation.soft_delete!(validate: false)
    redirect_to coworking_pack_path(@pack), notice: "La journée a été annulée."
  end

  private

  def get_pack
    @pack = CoworkingPack.find(params[:coworking_pack_id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "coworking"
    )
    @settings_view = true
  end
end
