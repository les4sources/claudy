module Portal
  # « Mes séjours » — la liste des séjours du client connecté au portail.
  #
  # Le scope part TOUJOURS de `current_portal_customer` : il n'y a aucun
  # paramètre d'identifiant client dans l'URL, donc rien à forger.
  class StaysController < Portal::BaseController
    before_action :require_portal_customer

    # Nombre de séjours passés montrés d'emblée ; le reste vit derrière un
    # « Voir plus » (disclosure natif <details>, sans JS ni dépendance).
    PAST_VISIBLE = 5

    def index
      stays = current_portal_customer.stays
                                     .includes(:customer, stay_items: :bookable)
                                     .order(Arel.sql("departure_date >= CURRENT_DATE DESC, arrival_date ASC"))

      decorated = StayDecorator.decorate_collection(stays)
      today = Date.current

      # « À venir » = pas encore terminé (départ aujourd'hui ou plus tard, ou
      # date de départ absente — on ne range pas un séjour sans date dans les
      # archives). Le reste est « passé ».
      @upcoming, @past = decorated.partition do |stay|
        stay.departure_date.blank? || stay.departure_date >= today
      end

      # À venir : le plus proche d'abord. Passés : le plus récent d'abord.
      @upcoming = @upcoming.sort_by { |s| s.arrival_date || Date.new(9999) }
      @past = @past.sort_by { |s| s.departure_date || Date.new(0) }.reverse

      @past_visible = @past.first(PAST_VISIBLE)
      @past_hidden = @past.drop(PAST_VISIBLE)
    end
  end
end
