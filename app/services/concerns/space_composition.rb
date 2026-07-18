# Composition d'ESPACES d'un séjour depuis un `Reservations::Draft` (epic #66,
# Phase 2). Concern PARTAGÉ par `Reservations::Builder` (création) et
# `Stays::AdminUpdater` (édition) : les deux traduisent les espaces choisis
# (`space_slots` grille nuit-par-nuit OU `halls` ponctuels {kind, date, period})
# en un `SpaceBooking` + ses `SpaceReservation`, rattaché au séjour via un
# `StayItem`.
#
# Réutilisation maximale (décision figée) :
#   - la disponibilité reste CAPACITY-AWARE via `Space#available_on?` (source
#     unique de vérité, comme `SpaceBookable#available?`) ;
#   - le montant de l'espace vient du devis B2C (`PricingModel`, part `:space`),
#     jamais recalculé ici.
#
# ⚠️ MAPPING clé de pricing → `Space` (à surveiller — voir gap connu) : le funnel
# public price les espaces avec des clés forfaitaires (`grande_salle`, …) qui ne
# correspondent pas 1:1 aux `Space.name` en base (seed : « Tilleul », « Saule »).
# On résout donc par une LISTE de noms candidats par clé, tolérante aux deux
# conventions (nom marketing OU nom du seed). Si aucune `Space` ne matche, la
# ligne reste dans le devis mais n'est pas persistée (voir `unresolved_space_keys`).
module SpaceComposition
  extend ActiveSupport::Concern

  # Noms de `Space` acceptés pour chaque clé de pricing, par ordre de préférence.
  # Le premier trouvé en base gagne. Cf. `PricingModel::SPACE_NAMES`.
  SPACE_NAMES_BY_KEY = {
    "grande_salle" => ["Grande Salle", "Tilleul"],
    "petite_salle" => ["Petite Salle", "Saule"],
    "cuisine_pro"  => ["Cuisine professionnelle", "Cuisine pro"]
  }.freeze

  private

  # Le draft porte-t-il au moins un espace exploitable (résolu ou non) ?
  # Sert au gate « contenu réservable » (un séjour peut être espaces-seuls).
  def draft_has_spaces?(draft)
    raw_space_entries(draft).any?
  end

  # Specs de réservation d'espace RÉSOLUES : [{ space:, date:, duration: }].
  # Ne contient que les entrées dont la `Space` existe en base.
  def space_reservation_specs(draft)
    raw_space_entries(draft).filter_map do |entry|
      space = space_for_key(entry[:key])
      next if space.nil?
      { space: space, date: entry[:date], duration: entry[:duration] }
    end
  end

  # Clés d'espace demandées mais SANS `Space` correspondante en base — utile pour
  # avertir l'admin (le devis les compte, mais elles ne seront pas persistées).
  def unresolved_space_keys(draft)
    raw_space_entries(draft)
      .map { |e| e[:key] }
      .uniq
      .reject { |key| space_for_key(key) }
  end

  # Conflits capacity-aware : (space, date) déjà plein (`Space#available_on?`).
  # Retourne les specs en conflit (vide = tout dispo).
  def space_availability_conflicts(specs)
    specs.reject { |spec| spec[:space].available_on?(spec[:date]) }
  end

  # Crée un `SpaceBooking` + ses `SpaceReservation` à partir de specs résolues,
  # et le rattache au séjour via un `StayItem`. Retourne le `SpaceBooking`.
  # `window` = [arrival_date, departure_date] du draft, pour fixer from/to_date
  # sur la fenêtre du séjour (cohérent avec `Stay#recompute_aggregates!`).
  def persist_space_booking!(stay:, draft:, specs:, status:, price_cents:)
    space_booking = build_space_booking(draft: draft, specs: specs, status: status, price_cents: price_cents)
    space_booking.save!
    stay.stay_items.create!(bookable: space_booking)
    space_booking
  end

  def build_space_booking(draft:, specs:, status:, price_cents:)
    dates = specs.map { |s| s[:date] }.compact
    space_booking = SpaceBooking.new(
      firstname:      draft.first_name,
      lastname:       draft.last_name,
      email:          Customer.normalize_email(draft.email),
      phone:          draft.phone,
      group_name:     draft.group_name,
      from_date:      draft.arrival_date || dates.min,
      to_date:        draft.departure_date || dates.max,
      status:         status,
      payment_status: "pending",
      price_cents:    price_cents
    )
    space_booking.generate_token
    specs.each do |spec|
      space_booking.space_reservations.build(space: spec[:space], date: spec[:date], duration: spec[:duration])
    end
    space_booking
  end

  # Réservable d'espace déjà rattaché au séjour (édition), ou nil.
  def existing_space_booking(stay)
    stay.stay_items.where(bookable_type: "SpaceBooking").first&.bookable
  end

  # --- Interne ------------------------------------------------------------

  # Entrées d'espace BRUTES (avant résolution `Space`) : [{ key:, date:, duration: }].
  # Fusionne les deux représentations : `space_slots` (grille nuit-par-nuit,
  # indexée depuis `arrival_date`) et `halls` (ponctuels {kind, date, period}).
  def raw_space_entries(draft)
    entries = []

    slots   = draft.space_slots
    arrival = draft.arrival_date
    if slots.present? && arrival.present?
      slots.each do |key, periods|
        next unless SPACE_NAMES_BY_KEY.key?(key.to_s)
        Array(periods).each_with_index do |period, night_idx|
          next if period.blank?
          entries << { key: key.to_s, date: arrival + night_idx, duration: period.to_s }
        end
      end
    end

    Array(draft.halls).each do |hall|
      hall = hall.symbolize_keys if hall.respond_to?(:symbolize_keys)
      key    = hall[:kind].to_s
      period = hall[:period].to_s
      next unless SPACE_NAMES_BY_KEY.key?(key)
      next if period.blank?
      date = parse_space_date(hall[:date])
      next if date.nil?
      entries << { key: key, date: date, duration: period }
    end

    entries
  end

  def space_for_key(key)
    @space_by_key ||= {}
    return @space_by_key[key.to_s] if @space_by_key.key?(key.to_s)

    names = SPACE_NAMES_BY_KEY[key.to_s]
    space = names && Space.where(name: names).min_by { |s| names.index(s.name) || 99 }
    @space_by_key[key.to_s] = space
  end

  def parse_space_date(value)
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
