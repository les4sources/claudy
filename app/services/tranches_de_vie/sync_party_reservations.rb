module TranchesDeVie
  # Répercute ici les annulations et remboursements décidés là-bas (issue #339).
  #
  # Une party remboursée sort du total du séjour et son paiement sort de
  # l'encaissé (statut `refunded`), mais la LIGNE RESTE VISIBLE : la compta doit
  # voir l'historique, pas le trou qu'il laisse. Un 404 sur la commande vaut une
  # annulation — une commande disparue chez eux n'existe plus ici non plus.
  class SyncPartyReservations < ServiceBase
    attr_reader :checked, :changed, :failures

    def initialize(scope: nil, client: Client.new)
      @scope = scope
      @client = client
      @checked = 0
      @changed = 0
      @failures = []
      @report_errors = false
    end

    def run
      catch_error { run! }
    end

    def run!
      raise ServiceError, "Connexion à Tranches de Vie non configurée" unless @client.configured?

      reservations.find_each do |reservation|
        @checked += 1
        sync_one(reservation)
      end
      true
    end

    def self.for_stay(stay, client: Client.new)
      new(scope: stay.party_reservations.active, client: client)
    end

    private

    def reservations
      @scope || PartyReservation.active
    end

    def sync_one(reservation)
      mapper = OrderMapper.new(@client.order(reservation.external_id))
      apply(reservation, mapper.sync_attributes)
    rescue Client::NotFound
      # Disparue de l'autre côté : on la traite comme annulée.
      apply(reservation, status: "cancelled", external_refunded_at: Time.current, synced_at: Time.current)
    rescue Client::Error => e
      # Une party injoignable ne doit pas arrêter les autres : on note et on passe.
      @failures << [reservation.id, e.message]
      reservation.update_columns(synced_at: Time.current)
    end

    def apply(reservation, attributes)
      previous_status = reservation.status
      reservation.update!(attributes)
      return if reservation.status == previous_status

      @changed += 1
      # L'argent suit le statut : une party qui sort du total sort de
      # l'encaissé, une party qui redevient active y revient.
      reservation.payment&.update!(status: reservation.active? ? "paid" : "refunded")
      reservation.stay.recompute_aggregates!
      reservation.stay.set_payment_status
    end
  end
end
