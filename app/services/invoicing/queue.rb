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
  #
  # Depuis 2026-09-02 le SÉJOUR porte lui aussi la colonne, et c'est le seul
  # endroit où l'équipe peut désormais demander une facture (le formulaire
  # Booking qui le permettait a disparu avec l'epic #81). Les deux réservables
  # restent lus pour l'historique importé — mais un séjour déjà présent dans la
  # file MASQUE ses propres réservables : une facture, une ligne.
  class Queue
    REQUESTED = "requested".freeze
    SENT      = "sent".freeze
    # Valeur historique posée par l'import quand le tarif n'a pas été tranché.
    UNDEFINED_TIER = "non défini".freeze
    # Les deux orthographes de l'annulation en base : l'app pose `canceled`
    # (réservables, filtres du calendrier), l'import a laissé des `cancelled`.
    CANCELED_STATUSES = %w[canceled cancelled].freeze

    # Une ligne facturable, quel que soit le modèle d'origine. `kind` porte la
    # clé technique (« booking » / « space_booking ») attendue par la route de
    # changement de statut.
    Line = Struct.new(:record, :kind, :label, :from_date, :to_date, :price_cents,
                      :status, :invoice_status, :stay, keyword_init: true) do
      def id = record.id

      # Une facture ne peut pas partir sans montant : la ligne le signale.
      def priceless? = price_cents.to_i.zero?

      # Année de rangement de l'historique des envois : celle de l'arrivée.
      # nil pour une ligne sans date (réservable historique incomplet).
      def year = from_date&.year
    end

    # Réservables historiques. Leur `tier` est la colonne du bloc « tarif non
    # tranché » — le séjour n'en a pas, d'où la distinction avec KINDS.
    BOOKABLE_KINDS = { "booking" => Booking, "space_booking" => SpaceBooking }.freeze
    KINDS = BOOKABLE_KINDS.merge("stay" => Stay).freeze

    # Libellé de la colonne « Type » de la file.
    KIND_LABELS = { "booking" => "Hébergement", "space_booking" => "Espaces",
                    "stay" => "Séjour" }.freeze

    def self.model_for(kind)
      KINDS.fetch(kind)
    end

    # Factures à fournir — le cœur du poste de travail, tri par date d'arrivée
    # (les séjours les plus anciens d'abord : ce sont les plus en retard).
    #
    # Une réservation ANNULÉE ne se facture pas (Michael 2026-09-06) : elle sort
    # de la file même si sa demande de facture est restée posée — sans quoi la
    # file affichait des séjours annulés comme du travail à faire.
    def requested
      @requested ||= lines_where({ invoice_status: REQUESTED }, exclude_canceled: true)
                     .sort_by { |l| l.from_date || Date.new(0) }
    end

    # Historique COMPLET des factures envoyées, rangé par année d'arrivée
    # (Michael 2026-09-06) : la facturation existe depuis 2023 sur les
    # réservables historiques, et une « mémoire courte » de 15 lignes la
    # rendait invisible. [[année, nombre], …], les plus récentes d'abord ; une
    # éventuelle année nil (ligne sans date) ferme la liste.
    def sent_years
      @sent_years ||= sent_lines.group_by(&:year)
                                .map { |year, lines| [year, lines.size] }
                                .sort_by { |year, _| year ? -year : 1 }
    end

    # Année affichée par défaut : la plus récente qui contient un envoi.
    def default_sent_year
      sent_years.first&.first
    end

    # Résout le paramètre `?year=` de la vue : une année connue de l'historique,
    # sinon l'année par défaut. Une valeur fantaisiste ne casse rien.
    def sent_year_for(param)
      return nil if param.to_s == UNDATED_YEAR_PARAM && sent_years.any? { |y, _| y.nil? }

      year = Integer(param, exception: false)
      return year if year && sent_years.any? { |y, _| y == year }

      default_sent_year
    end

    # Valeur de `?year=` qui désigne les envois SANS date d'arrivée.
    UNDATED_YEAR_PARAM = "sans-date".freeze

    # Factures envoyées d'UNE année, les plus récentes d'abord. Le bouton de la
    # vue fait le chemin inverse (« remettre à fournir »), d'où la conservation
    # du même format de ligne que la file.
    def sent_for_year(year)
      sent_lines.select { |l| l.year == year }
                .sort_by { |l| l.from_date || Date.new(0) }
                .reverse
    end

    # Réservations dont le TARIF n'a jamais été tranché : impossible d'émettre
    # une facture tant que le montant n'est pas décidé. Bloc d'alerte, pas file
    # de travail — d'où la restriction aux réservations encore actives.
    def undefined_tier
      @undefined_tier ||= lines_where({ tier: UNDEFINED_TIER, status: %w[confirmed pending] },
                                      kinds: BOOKABLE_KINDS)
    end

    private

    def sent_lines
      @sent_lines ||= lines_where({ invoice_status: SENT })
    end

    def lines_where(conditions, kinds: KINDS, exclude_canceled: false)
      lines = kinds.flat_map do |kind, model|
        scope = model.where(conditions)
        scope = without_canceled(scope) if exclude_canceled
        scope = model == Stay ? scope.includes(:customer, stay_items: :bookable) : scope.includes(:stay)
        scope.map { |record| build_line(record, kind) }
      end
      dedupe(lines)
    end

    # Les deux orthographes de l'annulation (`CANCELED_STATUSES`), et un statut
    # absent reste dans la file : `NOT IN` seul écarterait les NULL.
    def without_canceled(scope)
      scope.where(status: nil).or(scope.where.not(status: CANCELED_STATUSES))
    end

    # Un séjour porteur d'un statut de facture PARLE POUR SES RÉSERVABLES : si
    # l'un d'eux porte encore le même statut (héritage de l'import), sa ligne
    # ferait double emploi dans la même file. On garde la ligne « séjour ».
    def dedupe(lines)
      covered = lines.filter_map { |l| l.record.id if l.kind == "stay" }.to_set
      lines.reject { |l| l.kind != "stay" && covered.include?(l.stay&.id) }
    end

    def build_line(record, kind)
      return build_stay_line(record) if kind == "stay"

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

    # Ligne d'un SÉJOUR. Le nom affiché suit la même règle que partout ailleurs
    # dans l'app (`StayDecorator#display_name`) : nom du client, ou nom de groupe
    # porté par la réservation d'origine sur les séjours du client fourre-tout.
    # Le montant est le TOTAL du séjour, pas celui d'un réservable.
    def build_stay_line(stay)
      Line.new(
        record:         stay,
        kind:           "stay",
        label:          stay.decorate.display_name.presence || "Séjour ##{stay.id}",
        from_date:      stay.arrival_date,
        to_date:        stay.departure_date,
        price_cents:    stay.total_amount_cents,
        status:         stay.status,
        invoice_status: stay.invoice_status,
        stay:           stay
      )
    end
  end
end
