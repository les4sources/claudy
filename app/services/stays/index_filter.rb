module Stays
  # Filtres de l'index Séjours (Michael 2026-10-15) : le STATUT du dossier et
  # « reste un solde à payer ». Ils se combinent entre eux, avec le trimestre
  # affiché et avec la recherche (qui porte alors sur toute la période).
  #
  # Le statut se filtre en SQL. Le solde, lui, ne le peut pas : le reste dû
  # dépend de `Stay#payments` (union reconstituée par `IndexAmounts`) et du prix
  # CALCULÉ des activités en attente. On le filtre donc en Ruby, après le calcul
  # en lot des montants — la même source que la colonne « Solde dû » de la page,
  # si bien que le filtre et l'affichage ne peuvent pas se contredire.
  class IndexFilter
    # Clé de l'URL => statuts en base. « Annulé » couvre les deux orthographes
    # (cf. `Stay::CANCELED_STATUSES`).
    STATUSES = {
      "pending"       => %w[pending],
      "pre_confirmed" => %w[pre_confirmed],
      "confirmed"     => %w[confirmed],
      "canceled"      => Stay::CANCELED_STATUSES
    }.freeze

    # Associations que `IndexAmounts` lit en mémoire (items Booking pour les
    # paiements, activités pour l'exigible).
    AMOUNT_PRELOADS = [
      :stay_items,
      { experience_bookings: { experience_availability: :experience } }
    ].freeze

    attr_reader :status

    def initialize(params)
      @status      = params[:status].to_s.presence_in(STATUSES.keys)
      @balance_due = params[:solde].to_s == "1"
    end

    def balance_due?
      @balance_due
    end

    def active?
      status.present? || balance_due?
    end

    # Paramètres à reporter dans les liens de la page (trimestres, effacer…).
    def to_params
      { status: status, solde: (balance_due? ? "1" : nil) }.compact
    end

    def apply_status(relation)
      status ? relation.where(status: STATUSES.fetch(status)) : relation
    end

    # Un séjour annulé ne doit plus rien, même si son total n'a pas été encaissé :
    # il est donc hors du filtre « Solde à payer ».
    def keep?(stay, amount)
      return true unless balance_due?

      !stay.canceled? && amount.balance_due_cents.positive?
    end
  end
end
