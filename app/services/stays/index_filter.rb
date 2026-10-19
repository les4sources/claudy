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

    # Sans statut dans l'URL, la liste montre les séjours confirmés (Michael,
    # 2026-10-18) : c'est ce qu'on vient y regarder. « Tous » se demande donc
    # explicitement, par `status=all`. Un statut inconnu retombe sur le défaut.
    DEFAULT_STATUS = "confirmed"
    ALL            = "all"

    # Associations que `IndexAmounts` lit en mémoire (items Booking pour les
    # paiements, activités pour l'exigible).
    AMOUNT_PRELOADS = [
      :stay_items,
      { experience_bookings: { experience_availability: :experience } }
    ].freeze

    attr_reader :status, :referral

    def initialize(params)
      raw          = params[:status].to_s
      @all         = (raw == ALL)
      @status      = @all ? nil : (raw.presence_in(STATUSES.keys) || DEFAULT_STATUS)
      @balance_due = params[:solde].to_s == "1"
      # Apporteur (Michael, 2026-10-18) : les séjours venus par un lien
      # partenaire (`Stay::REFERRALS`), pour préparer ce qu'on lui reverse.
      @referral    = params[:apporteur].to_s.presence_in(Stay::REFERRALS.keys)
    end

    def balance_due?
      @balance_due
    end

    # « Tous » choisi : aucun filtre de statut.
    def all_statuses?
      @all
    end

    def active?
      status.present? || balance_due? || referral.present?
    end

    # Paramètres à reporter dans les liens de la page (trimestres, effacer…).
    # Le statut y est toujours explicite, « Tous » compris : sans lui, le lien
    # retomberait sur le défaut.
    def to_params
      { status: (all_statuses? ? ALL : status), solde: (balance_due? ? "1" : nil), apporteur: referral }.compact
    end

    # Filtres SQL : statut et apporteur.
    def apply_scopes(relation)
      relation = relation.where(status: STATUSES.fetch(status)) if status
      relation = relation.referred_by(referral) if referral
      relation
    end

    # Un séjour annulé ne doit plus rien, même si son total n'a pas été encaissé :
    # il est donc hors du filtre « Solde à payer ».
    def keep?(stay, amount)
      return true unless balance_due?

      !stay.canceled? && amount.balance_due_cents.positive?
    end
  end
end
