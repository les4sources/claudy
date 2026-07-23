# Composition HAMACS d'un séjour depuis un `Reservations::Draft` (issue #138).
# Concern PARTAGÉ par `Reservations::Builder` (création) et `Stays::AdminUpdater`
# (édition), sur le modèle exact de `CampingComposition` — dont il réutilise les
# primitives `night_value_ranges` / `distribute_cents` (déclarées en dépendance
# ci-dessous, pour ne pas dupliquer la découpe en plages ni la ventilation
# largest-remainder).
#
# Décisions (issue #138, décision Michael 2026-07-22) :
#   - Les hamacs sont PERSISTÉS, dans TOUS les canaux (funnel public ET admin) :
#     jusqu'ici ils n'existaient que dans le devis, donc invisibles du séjour et
#     sur-louables.
#   - Grille par nuit `per_night_resources["hamac_simple"|"hamac_double"]` →
#     une `HamacBooking` par PLAGE CONTIGUË de valeur constante, fenêtre
#     `[from, to)` — comme camping/van, donc calendrier et totaux marchent sans
#     traitement spécial.
#   - Le montant vient du devis (`quote.hamac_cents`), VENTILÉ sur les plages au
#     prorata `count × nuits` : ∑ plages == part hamac du devis (invariant).
#   - Capacité = STOCK physique du `RentalItem` (nil = non borné).
module HamacComposition
  extend ActiveSupport::Concern

  # `night_value_ranges`, `distribute_cents`, `draft_window_nights`,
  # `draft_per_night_grid?` et `symbol` vivent dans CampingComposition.
  include CampingComposition

  # Clé de la grille `per_night_resources` pour un type de hamac.
  GRID_KEYS = { "simple" => "hamac_simple", "double" => "hamac_double" }.freeze

  private

  # --- Lecture du draft ----------------------------------------------------

  # Entrées hamac du draft, normalisées `{kind:, count:, nights:}`. Le Draft les
  # dérive lui-même de la grille quand elle est présente ; sinon ce sont les
  # entrées pleine-fenêtre (form legacy / emails).
  def draft_hamac_entries(draft)
    Array(draft.try(:hamacs)).map { |e| symbol(e) }
                             .select { |e| HamacBooking::KINDS.include?(e[:kind].to_s) && e[:count].to_i.positive? }
  end

  def draft_has_hamacs?(draft)
    draft_hamac_entries(draft).any?
  end

  # Plages contiguës pour un type de hamac, depuis la grille par nuit.
  def hamac_night_ranges(draft, kind)
    night_value_ranges(
      draft.per_night_resources&.[](GRID_KEYS.fetch(kind.to_s)),
      draft.arrival_date,
      max_nights: draft_window_nights(draft)
    )
  end

  # Toutes les plages hamac, par type : `{ "simple" => [...], "double" => [...] }`
  # (types sans plage exclus).
  def hamac_ranges_by_kind(draft)
    HamacBooking::KINDS.each_with_object({}) do |kind, memo|
      ranges = hamac_night_ranges(draft, kind)
      memo[kind] = ranges if ranges.any?
    end
  end

  # Repli pleine-fenêtre (grille absente) : une plage par type, agrégeant les
  # entrées de ce type sur toute la fenêtre du séjour. Même forme de retour que
  # `hamac_ranges_by_kind` pour que la persistance n'ait qu'un seul chemin.
  def hamac_full_window_ranges_by_kind(draft)
    return {} if draft.arrival_date.blank? || draft.departure_date.blank?
    nights = draft_window_nights(draft).to_i
    return {} if nights < 1

    draft_hamac_entries(draft).group_by { |e| e[:kind].to_s }.transform_values do |entries|
      count = entries.sum { |e| e[:count].to_i }
      [{ from_date: draft.arrival_date, to_date: draft.departure_date,
         nights: nights, value: count }]
    end
  end

  # Source unique des plages à persister : grille si elle porte des hamacs,
  # repli pleine-fenêtre sinon.
  def hamac_ranges_for(draft)
    grid = draft_per_night_grid?(draft) ? hamac_ranges_by_kind(draft) : {}
    grid.any? ? grid : hamac_full_window_ranges_by_kind(draft)
  end

  # --- Stock (RentalItem) --------------------------------------------------

  # Message d'avertissement si la demande dépasse le stock disponible une nuit
  # donnée, sinon nil. `excluding_id` : réservations propres au séjour édité.
  def hamac_stock_message(draft, excluding_id: nil)
    hamac_ranges_for(draft).each do |kind, ranges|
      ranges.each do |r|
        date = HamacBooking.capacity_conflict_date(
          kind: kind, units: r[:value], from: r[:from_date], to: r[:to_date],
          excluding_id: excluding_id
        )
        next if date.nil?

        stock = HamacBooking.total_stock(kind)
        return "#{HamacBooking.label_for(kind)} : stock insuffisant le " \
               "#{date.strftime('%-d/%m')} (#{stock} disponible#{'s' if stock.to_i > 1})."
      end
    end
    nil
  end

  # --- Persistance ---------------------------------------------------------

  # Persiste les hamacs du draft en N `HamacBooking` (une par plage contiguë et
  # par type). `total_price_cents` (= `quote.hamac_cents`) est VENTILÉ sur TOUTES
  # les plages, tous types confondus, au prorata `count × nuits × tarif` : la
  # somme des `price_cents` égale EXACTEMENT la part hamac du devis.
  def persist_hamac_ranges!(stay:, draft:, status:, total_price_cents:)
    flat = hamac_ranges_for(draft).flat_map { |kind, ranges| ranges.map { |r| r.merge(kind: kind) } }
    return [] if flat.empty?

    # Poids pondérés par le TARIF du type : un hamac double coûte le double d'un
    # simple, la ventilation doit le refléter (sinon un séjour mixte répartirait
    # à tort le total à parts égales entre simples et doubles).
    weights = flat.map { |r| r[:value] * r[:nights] * hamac_rate_for(r[:kind]) }
    prices  = distribute_cents(total_price_cents, weights)

    flat.each_with_index.map do |r, idx|
      hamac = HamacBooking.new(
        firstname:   draft.first_name, lastname: draft.last_name,
        email:       Customer.normalize_email(draft.email), phone: draft.phone,
        group_name:  draft.group_name,
        from_date:   r[:from_date], to_date: r[:to_date],
        kind:        r[:kind], count: [r[:value], 1].max,
        status:      status, price_cents: prices[idx]
      )
      hamac.save!
      stay.stay_items.create!(bookable: hamac)
      hamac
    end
  end

  # Tarif unitaire d'un type de hamac, borné à 1 pour ne jamais annuler le poids
  # d'une plage (un tarif nul rendrait la ventilation dégénérée).
  def hamac_rate_for(kind)
    [Pricing::Catalog.hamac_rate(kind).to_i, 1].max
  end

  # HamacBooking déjà rattachés au séjour (édition).
  def existing_hamac_bookings(stay)
    stay.stay_items.where(bookable_type: "HamacBooking").filter_map(&:bookable)
  end

  # Détache + soft-delete tous les HamacBooking du séjour. L'édition reconstruit
  # intégralement les plages (comme le camping) plutôt que de réconcilier N↔N.
  def detach_hamac_bookings!(stay)
    stay.stay_items.where(bookable_type: "HamacBooking").each do |item|
      item.bookable&.soft_delete!(validate: false)
      item.soft_delete!(validate: false)
    end
  end
end
