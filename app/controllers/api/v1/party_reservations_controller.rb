module Api
  module V1
    # Surface agent en LECTURE SEULE des Pizza Party rattachées (issue #339).
    # Une party se crée et se détache depuis la fiche séjour, jamais par l'API :
    # elle n'a de sens que rapportée à un séjour et à un paiement.
    class PartyReservationsController < BaseController
      def index
        scope = PartyReservation.all
        scope = scope.where(stay_id: params[:stay_id]) if params[:stay_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        @party_reservations = paginate(scope.includes(:stay, :payment).ordered)
      end

      def show
        @party_reservation = PartyReservation.includes(:stay, :payment).find(params[:id])
      end
    end
  end
end
