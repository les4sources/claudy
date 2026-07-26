module Invoicing
  # File de travail du Pôle Admin (Michael 2026-07-26) — remplace l'ancien
  # « Comptabilité / Tableau de bord ».
  #
  # Le problème que ça résout : la facturation vit sur DEUX modèles distincts
  # (`Booking` pour l'hébergement, `SpaceBooking` pour les espaces), chacun avec
  # ses colonnes `invoice_status` et `tier`. L'ancienne vue empilait donc quatre
  # tableaux quasi identiques. Ici on NORMALISE les deux en une même `Line`, et
  # la vue n'en connaît plus qu'une seule forme.
  #
  # `invoice_status` en base : "requested" (à fournir), "sent" (envoyée), et
  # "on" / "" / nil (non requise — la grande majorité).
  class Queue
    REQUESTED = "requested".freeze
    SENT      = "sent".freeze
    # Valeur historique posée par l'import quand le tarif n'a pas été tranché.
    UNDEFINED_TIER = "non défini".freeze

    # Une ligne facturable, quel que soit le modèle d'origine. `kind` porte la
    # clé technique (« booking » / « space_booking ») attendue par la route de
    # changement de statut.
    Line = Struct.new(:record, :kind, :label, :from_date, :to_date, :price_cents,
                      :status, :invoice_status, :stay, keyword_init: true) do
      def id = record.id

      # Une facture ne peut pas partir sans montant : la ligne le signale.
      def priceless? = price_cents.to_i.zero?
    end

    KINDS = { "booking" => Booking, "space_booking" => SpaceBooking }.freeze

    def self.model_for(kind)
      KINDS.fetch(kind)
    end

    # Factures à fournir — le cœur du poste de travail, tri par date d'arrivée
    # (les séjours les plus anciens d'abord : ce sont les plus en retard).
    def requested
      @requested ||= lines_where(invoice_status: REQUESTED).sort_by { |l| l.from_date || Date.new(0) }
    end

    # Factures déjà envoyées — mémoire courte, pour confirmer un envoi récent
    # sans polluer la file. Les plus récentes d'abord.
    def recently_sent(limit: 15)
      @recently_sent ||= lines_where(invoice_status: SENT)
                         .sort_by { |l| l.from_date || Date.new(0) }
                         .reverse
                         .first(limit)
    end

    # Réservations dont le TARIF n'a jamais été tranché : impossible d'émettre
    # une facture tant que le montant n'est pas décidé. Bloc d'alerte, pas file
    # de travail — d'où la restriction aux réservations encore actives.
    def undefined_tier
      @undefined_tier ||= lines_where(tier: UNDEFINED_TIER, status: %w[confirmed pending])
    end

    private

    def lines_where(conditions)
      KINDS.flat_map do |kind, model|
        scope = model.where(conditions).includes(:stay)
        scope.map { |record| build_line(record, kind) }
      end
    end

    def build_line(record, kind)
      Line.new(
        record:         record,
        kind:           kind,
        label:          record.try(:group_name).presence ||
                        [record.try(:firstname), record.try(:lastname)].compact_blank.join(" ").presence ||
                        "Réservation ##{record.id}",
        from_date:      record.try(:from_date),
        to_date:        record.try(:to_date),
        price_cents:    record.try(:price_cents),
        status:         record.try(:status),
        invoice_status: record.invoice_status,
        stay:           record.try(:stay)
      )
    end
  end
end
