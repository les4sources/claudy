module TranchesDeVie
  # Rattache une Pizza Party privée payée sur Tranches de Vie à un séjour.
  #
  # Deux écritures, dans une transaction : la `PartyReservation` (le miroir) et
  # son `Payment` (l'argent). La party est EXIGIBLE dès le rattachement — elle
  # est déjà payée — donc le total du séjour ET l'encaissé bougent du même
  # montant : un séjour soldé le reste.
  class AttachPartyReservation < ServiceBase
    attr_reader :stay, :party_reservation

    ALREADY_ATTACHED = "Cette Pizza Party est déjà rattachée à un séjour.".freeze
    NOT_PAID = "Cette Pizza Party n'est pas payée : rien à rattacher.".freeze

    def initialize(stay:, client: Client.new)
      @stay = stay
      @client = client
      @report_errors = false
    end

    def run(external_id)
      catch_error(context: { stay_id: stay.id, external_id: external_id }) { run!(external_id) }
    end

    def run!(external_id)
      mapper = OrderMapper.new(@client.order(external_id))
      raise ServiceError, ALREADY_ATTACHED if already_attached?(mapper.external_id)
      raise ServiceError, NOT_PAID unless mapper.status == "active"

      PartyReservation.transaction do
        @party_reservation = stay.party_reservations.create!(mapper.attributes)
        @party_reservation.update!(payment: build_payment!)
      end

      stay.recompute_aggregates!
      stay.set_payment_status
      true
    end

    private

    def already_attached?(external_id)
      PartyReservation.exists?(source: "tranchesdevie", external_id: external_id)
    end

    # Le paiement miroir. `Payments::CreateService` n'est pas utilisable ici :
    # il s'ancre sur un booking, et une party n'en a pas.
    def build_payment!
      Payment.create!(
        stay: stay,
        amount_cents: @party_reservation.price_cents,
        status: "paid",
        payment_method: Payment::TRANCHESDEVIE_METHOD,
        paid_on: @party_reservation.external_paid_at&.to_date
      )
    end
  end
end
