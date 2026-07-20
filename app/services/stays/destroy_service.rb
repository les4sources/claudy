module Stays
  # Suppression d'un séjour = soft-delete (soft_deletion + PaperTrail), jamais de
  # hard destroy. `Stay#soft_delete!` cascade nativement sur `stay_items` et
  # `meal_orders` (leurs classes portent `has_soft_deletion` → présentes dans
  # `soft_delete_dependents`), MAIS PAS sur les BOOKABLES : StayItem porte
  # l'occupation via une association polymorphe et le soft-delete du Stay ne
  # descend jamais jusqu'au Booking/SpaceBooking/CampingBooking/VanBooking.
  #
  # Sans ce service, supprimer un séjour laissait donc ses bookables — ET leurs
  # Reservation/SpaceReservation — VIVANTS : des blocs fantômes qui occupaient le
  # calendrier et posaient le veto de dispo, sans séjour d'attache (issue #99).
  #
  # On soft-delete donc explicitement chaque bookable AVANT le Stay (pendant que
  # les stay_items sont encore vivants et lisibles). Miroir des chemins de
  # détachement de `Stays::AdminUpdater` (reconcile_*!) :
  #
  #   - Booking       : sa cascade `dependent: :destroy` sur `reservations`
  #                     (elles-mêmes soft-deletables) rend les chambres au
  #                     calendrier et au veto ;
  #   - SpaceBooking  : ses `space_reservations` n'ont PAS de soft-deletion — le
  #                     veto/calendrier des espaces filtre déjà via le
  #                     `default_scope` du SpaceBooking soft-deleté, mais on
  #                     détruit les lignes explicitement (comme
  #                     `reconcile_spaces!` au rebuild) pour ne laisser AUCUNE
  #                     ligne d'occupation orpheline en base ;
  #   - Camping/Van   : occupation dérivée de leurs propres dates → le soft-delete
  #                     du bookable suffit.
  #
  # Les `Payment` sont PRÉSERVÉS (trace financière auditable) : aucune association
  # de paiement ne figure dans le `soft_delete_dependents` d'un bookable.
  class DestroyService < ServiceBase
    def initialize(stay:)
      @stay = stay
    end

    def run
      Stay.transaction do
        soft_delete_bookables!
        @stay.soft_delete!(validate: false)
      end
      true
    end

    private

    def soft_delete_bookables!
      @stay.bookables.each do |bookable|
        # SpaceReservation n'est pas soft-deletable et ne cascade pas depuis le
        # SpaceBooking : on retire ses lignes explicitement (hard-delete assumé,
        # la trace vit dans le SpaceBooking soft-deleté + PaperTrail).
        bookable.space_reservations.destroy_all if bookable.respond_to?(:space_reservations)
        bookable.soft_delete!(validate: false)
      end
    end
  end
end
