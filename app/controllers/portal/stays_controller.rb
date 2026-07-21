module Portal
  # « Mes séjours » — la liste des séjours du client connecté au portail.
  #
  # Le scope part TOUJOURS de `current_portal_customer` : il n'y a aucun
  # paramètre d'identifiant client dans l'URL, donc rien à forger.
  class StaysController < Portal::BaseController
    before_action :require_portal_customer

    def index
      stays = current_portal_customer.stays
                                     .includes(:customer, stay_items: :bookable)
                                     .order(Arel.sql("departure_date >= CURRENT_DATE DESC, arrival_date ASC"))

      @stays = StayDecorator.decorate_collection(stays)
    end
  end
end
