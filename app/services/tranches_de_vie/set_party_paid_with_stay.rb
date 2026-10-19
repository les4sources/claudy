module TranchesDeVie
  # Dit si une Pizza Party rattachée est réglée AVEC le séjour (un seul virement
  # du client aux 4 Sources, déjà dans l'encaissé) ou à part, chez Tranches de
  # Vie (Michael, 2026-10-19).
  #
  # Réglée avec le séjour : son paiement miroir sort de l'encaissé (soft-delete,
  # comme au détachement), la party reste dans le total. Réglée à part : le
  # paiement miroir revient si Tranches de Vie la voit payée.
  class SetPartyPaidWithStay < ServiceBase
    attr_reader :party_reservation, :stay

    def initialize(party_reservation:)
      @party_reservation = party_reservation
      @stay = party_reservation.stay
      @report_errors = false
    end

    def run(paid_with_stay)
      catch_error(context: { party_reservation_id: party_reservation.id }) { run!(paid_with_stay) }
    end

    def run!(paid_with_stay)
      PartyReservation.transaction do
        party_reservation.update!(paid_with_stay: paid_with_stay)
        payment = party_reservation.payment

        if party_reservation.paid_with_stay? && payment.present?
          party_reservation.update!(payment: nil)
          payment.soft_delete!(validate: false)
        elsif payment.nil? && AttachPartyReservation.mirror_payment_due?(party_reservation)
          party_reservation.update!(payment: AttachPartyReservation.build_payment!(party_reservation))
        end
      end

      stay.recompute_aggregates!
      stay.set_payment_status
      true
    end
  end
end
