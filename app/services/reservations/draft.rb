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
                  :adults, :children

    # Backing stores pour campings/vans/hamacs (utilisés quand per_night_resources absent)
    attr_writer :campings, :vans, :hamacs

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
      @first_name        = attrs[:first_name].presence
      @last_name         = attrs[:last_name].presence
      @email             = attrs[:email].presence
      @phone             = attrs[:phone].presence
      @group_name        = attrs[:group_name].presence
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
        first_name:         first_name,
        last_name:          last_name,
        email:              email,
        phone:              phone,
        group_name:         group_name
      }
    end

    def quote(deposit_rate: Pricing::Catalog::DEFAULT_DEPOSIT_RATE)
      PricingModel.quote(self, deposit_rate: deposit_rate)
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
