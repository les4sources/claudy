module Portal
  # Réservation et annulation d'une journée de coworking depuis le portail
  # (epic #126, Phase 3). Le scope part TOUJOURS de `current_portal_customer` :
  # on ne peut ni réserver ni annuler pour quelqu'un d'autre.
  class CoworkingReservationsController < Portal::BaseController
    before_action :require_portal_customer

    def create
      service = Coworking::ReserveDay.new(
        customer: current_portal_customer,
        date: parse_date(params[:date])
      )

      if service.run
        CoworkingMailer.reservation_confirmed(service.reservation).deliver_later
        redirect_to redirect_target, notice: "Journée réservée pour le #{l(service.reservation.date, format: :long)}."
      else
        redirect_to redirect_target, alert: service.error_message
      end
    end

    def destroy
      reservation = current_portal_customer.coworking_reservations.find(params[:id])
      service = Coworking::CancelDay.new(reservation: reservation)

      if service.run
        CoworkingMailer.reservation_cancelled(reservation).deliver_later
        redirect_to redirect_target, notice: "Journée du #{l(reservation.date, format: :long)} annulée."
      else
        redirect_to redirect_target, alert: service.error_message
      end
    end

    private

    def parse_date(raw)
      Date.iso8601(raw.to_s)
    rescue ArgumentError
      nil
    end

    # Revenir sur le mois affiché quand il est fourni, pour ne pas renvoyer le
    # client au mois courant après une action sur un mois futur.
    def redirect_target
      month = params[:month].presence
      month ? portal_coworking_path(month: month) : portal_coworking_path
    end
  end
end
