module TranchesDeVie
  # Traduit une commande Tranches de Vie (contrat les4sources/tranchesdevie2#290)
  # en attributs de `PartyReservation`. Isolé pour que le contrat n'ait qu'UN
  # point de contact dans le code : quand il bouge, on ne cherche pas.
  class OrderMapper
    def initialize(order)
      @order = order.to_h.with_indifferent_access
    end

    attr_reader :order

    def external_id = order[:id]
    def party = order[:party].presence || {}
    def customer = order[:customer].presence || {}

    def cancelled? = ActiveModel::Type::Boolean.new.cast(order[:cancelled]).present?
    def refunded?  = ActiveModel::Type::Boolean.new.cast(order[:refunded]).present?

    # Statut côté Claudy. Une commande annulée prime sur remboursée : c'est
    # l'information la plus forte pour la compta.
    def status
      return "cancelled" if cancelled?
      return "refunded" if refunded?

      "active"
    end

    def attributes
      {
        source: "tranchesdevie",
        external_id: external_id,
        external_number: order[:order_number],
        held_on: party[:held_on].presence,
        slot: party[:slot],
        group_name: party[:group_name],
        persons: party[:persons],
        forfait: ActiveModel::Type::Boolean.new.cast(party[:forfait]).present?,
        price_cents: order[:total_cents].to_i,
        status: status,
        external_paid_at: order[:paid_at].presence,
        external_admin_url: party[:admin_url],
        external_refunded_at: order[:refunded_at].presence,
        synced_at: Time.current,
        payload: order.to_h
      }
    end

    # Les attributs qu'une synchronisation met à jour. On ne réécrit pas
    # `external_id` ni `source` : ce sont les clés du miroir.
    def sync_attributes
      attributes.except(:source, :external_id)
    end

    def customer_email = customer[:email].to_s.downcase.presence
    def customer_phone = customer[:phone_e164].to_s.presence
    def customer_name  = customer[:full_name].to_s.presence

    def total_euros
      Money.new(order[:total_cents].to_i)
    end
  end
end
