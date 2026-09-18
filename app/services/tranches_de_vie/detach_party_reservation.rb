module TranchesDeVie
  # Détache une Pizza Party d'un séjour : le miroir ET son paiement partent en
  # soft-delete (jamais de destruction sèche — la compta doit pouvoir revenir en
  # arrière), puis les agrégats du séjour sont rejoués.
  #
  # Rien n'est écrit chez Tranches de Vie : la party y reste ce qu'elle est.
  class DetachPartyReservation < ServiceBase
    attr_reader :party_reservation, :stay

    def initialize(party_reservation:)
      @party_reservation = party_reservation
      @stay = party_reservation.stay
      @report_errors = false
    end

    def run
      catch_error(context: { party_reservation_id: party_reservation.id }) { run! }
    end

    def run!
      payment = party_reservation.payment

      PartyReservation.transaction do
        # La party d'abord : son paiement ne doit jamais rester orphelin d'un
        # miroir encore vivant, même une fraction de transaction.
        party_reservation.soft_delete!(validate: false)
        payment&.soft_delete!(validate: false)
      end

      stay.recompute_aggregates!
      stay.set_payment_status
      true
    end
  end
end
