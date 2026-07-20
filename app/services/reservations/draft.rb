module Reservations
  # Panier de séjour en cours de composition (B2C /reservation). PORO sérialisé
  # en session — aucune écriture DB tant que le client n'a pas soumis. Implémente
  # le contrat de stay_draft attendu par PricingModel (#lodging, #nights,
  # #dogs_count, #campings, #vans, #halls, #meals, #pizza_parties).
  #
  # FR-only (Q7), pas de politique d'annulation embarquée (Q8) : le draft ne
  # transporte que la composition tarifable.
  class Draft
    attr_accessor :lodging_id, :lodging_night_ids, :per_night_resources,
                  :arrival_date, :departure_date, :dogs_count,
                  :halls, :space_slots, :meals, :pizza_parties,
                  :experiences,
                  :first_name, :last_name, :email, :phone, :group_name,
                  # Client organisation vs particulier (form admin, addendum) :
                  # `customer_type` ("individual"/"organization") + le nom du
                  # groupe/organisation. Portés à la CRÉATION d'un nouveau client.
                  :customer_type, :organization_name,
                  :adults, :children,
                  # Chambres seules (epic #81, Phase 5) : mode d'occupation de
                  # l'hébergement — "lodging" (gîte entier, défaut) ou "rooms"
                  # (sous-ensemble de chambres du gîte). `room_ids` porte les
                  # chambres cochées ; il n'a de sens qu'en mode "rooms".
                  :booking_type

    # Facturation ESPACE (epic #81, Phase 6) : attributs portés par le
    # `SpaceBooking` du séjour (acompte, caution, mode de paiement, événement,
    # horaires). Vaut `nil` quand le form ne porte PAS la clé `space_billing` —
    # signal « ne pas toucher » à la réédition ; un Hash (même à valeurs vides)
    # signifie « appliquer tel quel » (champ vidé → nil, jamais 0 forcé).
    attr_reader :space_billing

    # Backing stores pour campings/vans/hamacs (utilisés quand per_night_resources absent)
    attr_writer :campings, :vans, :hamacs
    attr_writer :room_ids

    def initialize(attrs = {})
      attrs = (attrs || {}).symbolize_keys
      @lodging_id        = attrs[:lodging_id].presence
      @lodging_night_ids = Array(attrs[:lodging_night_ids]).map { |id| id.presence }
      @per_night_resources = parse_per_night_resources(attrs[:per_night_resources])
      @arrival_date      = parse_date(attrs[:arrival_date])
      @departure_date    = parse_date(attrs[:departure_date])
      @dogs_count        = attrs[:dogs_count].to_i
      @adults            = attrs[:adults].to_i
      @children          = attrs[:children].to_i
      @campings          = symbolize_rows(attrs[:campings])
      @vans              = symbolize_rows(attrs[:vans])
      @halls             = symbolize_rows(attrs[:halls])
      @space_slots       = parse_space_slots(attrs[:space_slots])
      @meals             = symbolize_rows(attrs[:meals])
      @pizza_parties     = symbolize_rows(attrs[:pizza_parties])
      @hamacs            = symbolize_rows(attrs[:hamacs])
      @experiences       = symbolize_rows(attrs[:experiences])
      @booking_type      = attrs[:booking_type].presence
      @room_ids          = normalize_room_ids(attrs[:room_ids])
      @space_billing     = normalize_space_billing(attrs[:space_billing])
      @first_name        = attrs[:first_name].presence
      @last_name         = attrs[:last_name].presence
      @email             = attrs[:email].presence
      @phone             = attrs[:phone].presence
      @group_name        = attrs[:group_name].presence
      @customer_type     = attrs[:customer_type].presence || "individual"
      @organization_name = attrs[:organization_name].presence
    end

    # --- Contrat PricingModel ---------------------------------------------

    def lodging
      id = lodging_night_ids.compact.first.presence || lodging_id
      @lodging ||= id.present? ? Lodging.find_by(id: id) : nil
    end

    def nights
      return 0 if arrival_date.blank? || departure_date.blank?
      (departure_date - arrival_date).to_i.clamp(0, 10_000)
    end

    # --- Chambres seules (epic #81, Phase 5) ------------------------------

    # Ids des chambres cochées (Integer, dédupliqués). Vide hors mode "rooms".
    def room_ids
      Array(@room_ids)
    end

    # L'occupation vise-t-elle un SOUS-ENSEMBLE de chambres (et non le gîte
    # entier) ? Piloté par le seul `booking_type` — l'UI le fixe explicitement.
    # `room_ids` peut être vide (rien de coché) : c'est alors une saisie
    # incomplète, tranchée par la validation du Builder/Updater, pas ici.
    def rooms_mode?
      booking_type.to_s == "rooms"
    end

    # Quand per_night_resources présent, on calcule depuis les comptes per-nuit.
    # Sinon, on retourne le backing store @campings (backward compat).
    def campings
      pnr = per_night_resources
      return @campings if pnr.blank?

      Array(pnr["tente"]).filter_map do |people|
        next if people.to_i < 1
        { kind: "tente", people: people.to_i, nights: 1 }
      end
    end

    def vans
      pnr = per_night_resources
      return @vans if pnr.blank?

      Array(pnr["van"]).filter_map do |count|
        next if count.to_i < 1
        { nights: 1 }
      end
    end

    def hamacs
      pnr = per_night_resources
      return @hamacs if pnr.blank?

      result = []
      %w[simple double].each do |kind|
        Array(pnr["hamac_#{kind}"]).each do |count|
          next if count.to_i < 1
          result << { kind: kind, count: count.to_i, nights: 1 }
        end
      end
      result
    end

    # --- Sérialisation session --------------------------------------------

    def to_h
      {
        lodging_id:         lodging_id,
        lodging_night_ids:  lodging_night_ids,
        per_night_resources: per_night_resources,
        arrival_date:       arrival_date&.iso8601,
        departure_date:     departure_date&.iso8601,
        dogs_count:         dogs_count,
        adults:             adults,
        children:           children,
        campings:           campings,
        vans:               vans,
        halls:              halls,
        space_slots:        space_slots,
        meals:              meals,
        pizza_parties:      pizza_parties,
        hamacs:             hamacs,
        experiences:        experiences,
        booking_type:       booking_type,
        room_ids:           room_ids,
        space_billing:      space_billing,
        first_name:         first_name,
        last_name:          last_name,
        email:              email,
        phone:              phone,
        group_name:         group_name,
        customer_type:      customer_type,
        organization_name:  organization_name
      }
    end

    def quote(deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE)
      PricingModel.quote(self, deposit_rate: deposit_rate)
    end

    # Le draft porte-t-il au moins une activité exploitable (créneau + participants) ?
    # Sert au gate « contenu réservable » élargi (séjour activités-seules, issue #80).
    def bookable_experiences?
      Array(experiences).any? do |entry|
        entry = entry.symbolize_keys if entry.respond_to?(:symbolize_keys)
        entry[:availability_id].present? && entry[:participants].to_i >= 1
      end
    end

    private

    def parse_date(value)
      return value if value.is_a?(Date)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def symbolize_rows(rows)
      Array(rows).map { |row| row.respond_to?(:symbolize_keys) ? row.symbolize_keys : row }
    end

    # Chambres cochées → Integer dédupliqués, ordre stable, sans zéro/blanc.
    def normalize_room_ids(ids)
      Array(ids).map { |id| id.to_i }.reject(&:zero?).uniq
    end

    # Facturation espace → Hash normalisé à clés symboles, ou nil si la clé est
    # absente (« ne pas toucher »). Chaque valeur est ramenée à nil quand elle est
    # vide : les montants (`advance_amount`/`deposit_amount`) restent des chaînes €
    # brutes, converties en cents par les setters `monetize` du SpaceBooking —
    # même conversion EXACTE que le canal direct `SpaceBookings::CreateService`.
    def normalize_space_billing(raw)
      return nil if raw.nil?
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      raw = raw.symbolize_keys
      {
        advance_amount: raw[:advance_amount].presence,
        deposit_amount: raw[:deposit_amount].presence,
        payment_method: raw[:payment_method].presence,
        event_id:       raw[:event_id].presence,
        arrival_time:   raw[:arrival_time].presence,
        departure_time: raw[:departure_time].presence
      }
    end

    def parse_per_night_resources(pnr)
      return {} if pnr.blank?
      pnr = pnr.respond_to?(:to_unsafe_h) ? pnr.to_unsafe_h : pnr.to_h
      pnr.transform_keys(&:to_s).transform_values { |arr| Array(arr).map { |v| v.to_s } }
    end

    def parse_space_slots(slots)
      return {} if slots.blank?
      h = slots.respond_to?(:to_unsafe_h) ? slots.to_unsafe_h : slots.to_h
      h.transform_keys(&:to_s).transform_values { |arr| Array(arr).map(&:to_s) }
    end
  end
end
