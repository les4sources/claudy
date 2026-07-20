# Composition CAMPING & VAN d'un séjour depuis un `Reservations::Draft`
# (epic #66, Phase 3). Concern PARTAGÉ par `Reservations::Builder` (création) et
# `Stays::AdminUpdater` (édition), sur le modèle de `SpaceComposition`.
#
# Décisions figées (Michael, 2026-07-18) :
#   - Camping = capacité GLOBALE du terrain (pas d'emplacements nommés). Un
#     `CampingBooking` occupe N personnes sur la fenêtre du séjour, vérifié
#     contre `CampingBooking::TOTAL_CAPACITY` (forçable par l'admin).
#   - Van / camping-car = même logique, en VÉHICULES, contre
#     `VanBooking::TOTAL_CAPACITY`.
#   - Les deux OCCUPENT le calendrier → rattachés via `StayItem` polymorphe, avec
#     from_date/to_date = fenêtre du séjour (comme Booking/SpaceBooking).
#   - Le montant vient du devis B2C (`PricingModel`, parts `:camping` / `:van`),
#     jamais recalculé ici — aucun double-compte avec `lodging_only_cents`.
module CampingComposition
  extend ActiveSupport::Concern

  private

  # --- Lecture du draft ----------------------------------------------------

  # Nombre total de personnes en camping demandé (agrège les entrées du draft).
  def draft_camping_people(draft)
    Array(draft.campings).sum { |e| symbol(e)[:people].to_i.clamp(0, 100_000) }
  end

  def draft_has_camping?(draft)
    draft_camping_people(draft).positive?
  end

  # Occupation SIMULTANÉE (pic) de personnes camping — valeur à PERSISTER sur le
  # `CampingBooking`, qui couvre toute la fenêtre en UN enregistrement. Les deux
  # représentations du draft convergent : admin = une entrée `{people, nights}`,
  # public = une entrée `{people, nights: 1}` par nuit (issue #79). Le pic = max
  # des `people` par entrée — cohérent avec le prix (people × nuits == person-nuits
  # facturées) sur le cas uniforme, et identique à la valeur admin actuelle.
  def draft_camping_peak_people(draft)
    Array(draft.campings).map { |e| symbol(e)[:people].to_i }.max.to_i
  end

  # Véhicules SIMULTANÉS (pic) à persister sur le `VanBooking`. Admin encode N
  # véhicules en N entrées couvrant toute la fenêtre (`nights == window`) ; le
  # public encode la présence par nuit en 1 entrée `{nights: 1}` par nuit (issue
  # #79, où le funnel plafonne de fait à un van). Le pic = nombre d'entrées
  # couvrant la fenêtre entière (admin) ; à défaut (public), 1.
  def draft_van_peak_vehicles(draft)
    entries = Array(draft.vans).map { |e| symbol(e) }
    return 0 if entries.empty?

    window   = [draft.nights, 1].max
    spanning = entries.count { |e| e[:nights].to_i >= window }
    spanning.positive? ? spanning : 1
  end

  # Nombre de véhicules demandés — une entrée `vans` = un véhicule (contrat
  # PricingModel : `van_lines` produit une ligne par entrée).
  def draft_van_vehicles(draft)
    Array(draft.vans).count { |e| (symbol(e)[:nights] || draft.nights).to_i.positive? }
  end

  def draft_has_van?(draft)
    draft_van_vehicles(draft).positive?
  end

  # --- Grille par nuit → plages contiguës (décision Michael 2026-07-20) -----
  #
  # Le funnel expose une grille `per_night_resources = { "tente" => [2,2,0,3],
  # "van" => [...] }` (une valeur par nuit, indexée depuis l'arrivée). On la
  # PERSISTE HONNÊTEMENT en N réservables, un par PLAGE CONTIGUË de valeur
  # constante non nulle : `[2,2,0,3]` → CampingBooking(nuits 1-2, 2 pers) +
  # CampingBooking(nuit 4, 3 pers). Chaque plage porte from/to = [nuit_début,
  # nuit_fin+1) — même convention `[from, to)` que Booking/SpaceBooking — donc
  # tout l'existant (calendrier, capacité, totaux) fonctionne sans modification.

  # Le draft porte-t-il la grille par nuit (funnel / form admin parité) ?
  # Sinon on retombe sur la représentation pleine-fenêtre (`campings`/`vans`).
  def draft_per_night_grid?(draft)
    draft.respond_to?(:per_night_resources) && draft.per_night_resources.present?
  end

  # Plages camping depuis la grille `per_night_resources["tente"]`.
  def camping_night_ranges(draft)
    night_value_ranges(draft.per_night_resources&.[]("tente"), draft.arrival_date, max_nights: draft_window_nights(draft))
  end

  # Plages van depuis la grille `per_night_resources["van"]`.
  def van_night_ranges(draft)
    night_value_ranges(draft.per_night_resources&.[]("van"), draft.arrival_date, max_nights: draft_window_nights(draft))
  end

  # Découpe un tableau de valeurs par nuit (indexé depuis `arrival_date`) en
  # plages contiguës de valeur constante NON NULLE. Retourne
  # `[{from_date:, to_date:, nights:, value:}, ...]` — `to_date` exclusif.
  # Nombre de nuits de la fenêtre du séjour (nil si dates absentes — la grille
  # n'est de toute façon pas dérivable sans arrivée).
  def draft_window_nights(draft)
    return nil if draft.arrival_date.blank? || draft.departure_date.blank?
    [(draft.departure_date - draft.arrival_date).to_i, 0].max
  end

  def night_value_ranges(values, arrival_date, max_nights: nil)
    ints = Array(values).map { |v| v.to_i }
    # Revue Forge F1 : la longueur de la grille vient du CLIENT — bornée à la
    # fenêtre du séjour, sinon un tableau forgé plus long créerait des plages
    # (prix + occupation) AU-DELÀ du départ.
    ints = ints.first(max_nights) if max_nights
    return [] if arrival_date.blank?

    ranges = []
    i = 0
    n = ints.length
    while i < n
      v = ints[i]
      if v <= 0
        i += 1
        next
      end
      j = i
      j += 1 while j < n && ints[j] == v
      ranges << { from_date: arrival_date + i, to_date: arrival_date + j,
                  nights: j - i, value: v }
      i = j
    end
    ranges
  end

  # Ventile un total en cents sur des plages, au prorata de leurs poids
  # (`value × nights`), le reste de division allant aux plus fortes parts
  # fractionnaires (largest-remainder). Somme EXACTEMENT égale à `total` —
  # c'est l'invariant asserté en spec : ∑ plages == part camping/van du devis.
  # Sur le cas uniforme, chaque plage porte exactement `people × nuits × tarif`.
  def distribute_cents(total, weights)
    total = total.to_i
    sum = weights.sum
    return Array.new(weights.size, 0) if sum <= 0

    base = weights.map { |w| total * w / sum }
    remainder = total - base.sum
    order = weights.each_index.sort_by { |i| [-((total * weights[i]) % sum), i] }
    remainder.times { |k| base[order[k % base.size]] += 1 }
    base
  end

  # --- Disponibilité capacité globale (forçable) ---------------------------

  # Renvoie un message d'avertissement si la demande dépasse la capacité globale,
  # sinon nil. Hors force, l'appelant transforme le message en erreur bloquante.
  # `excluding_camping_id` / `excluding_van_id` : réservations propres au séjour à
  # ignorer (édition — sinon l'édition d'un séjour camping-seul se bloque elle-même).
  def camping_capacity_message(draft, excluding_id: nil)
    people = draft_camping_people(draft)
    return nil if people.zero?
    date = CampingBooking.capacity_conflict_date(
      units: people, from: draft.arrival_date, to: draft.departure_date, excluding_id: excluding_id
    )
    return nil if date.nil?
    "Camping complet le #{date.strftime('%-d/%m')} (capacité #{CampingBooking::TOTAL_CAPACITY} pers)."
  end

  def van_capacity_message(draft, excluding_id: nil)
    vehicles = draft_van_vehicles(draft)
    return nil if vehicles.zero?
    date = VanBooking.capacity_conflict_date(
      units: vehicles, from: draft.arrival_date, to: draft.departure_date, excluding_id: excluding_id
    )
    return nil if date.nil?
    "Emplacements van complets le #{date.strftime('%-d/%m')} (capacité #{VanBooking::TOTAL_CAPACITY} véhicules)."
  end

  # Messages capacité GRILLE (par nuit) : chaque nuit demandée est confrontée à
  # SA propre demande (pas la somme des nuits — sinon un séjour [2,2,0,3] serait
  # évalué à 7 pers/nuit à tort). Renvoie le 1er conflit, ou nil.
  def camping_grid_capacity_message(draft, excluding_id: nil)
    camping_night_ranges(draft).each do |r|
      date = CampingBooking.capacity_conflict_date(
        units: r[:value], from: r[:from_date], to: r[:to_date], excluding_id: excluding_id
      )
      return "Camping complet le #{date.strftime('%-d/%m')} (capacité #{CampingBooking.total_capacity} pers)." if date
    end
    nil
  end

  def van_grid_capacity_message(draft, excluding_id: nil)
    van_night_ranges(draft).each do |r|
      date = VanBooking.capacity_conflict_date(
        units: r[:value], from: r[:from_date], to: r[:to_date], excluding_id: excluding_id
      )
      return "Emplacements van complets le #{date.strftime('%-d/%m')} (capacité #{VanBooking.total_capacity} véhicules)." if date
    end
    nil
  end

  # --- Persistance ---------------------------------------------------------

  # Persiste la grille camping en N CampingBooking (une par plage contiguë). Le
  # `total_price_cents` (= `quote.camping_cents`) est VENTILÉ sur les plages au
  # prorata `people × nuits` : ∑ price_cents == total (invariant devis). Retourne
  # les CampingBooking créés (peut être vide si la grille est toute nulle).
  def persist_camping_ranges!(stay:, draft:, status:, total_price_cents:)
    ranges  = camping_night_ranges(draft)
    return [] if ranges.empty?
    prices  = distribute_cents(total_price_cents, ranges.map { |r| r[:value] * r[:nights] })
    ranges.each_with_index.map do |r, idx|
      camping = CampingBooking.new(
        firstname:   draft.first_name, lastname: draft.last_name,
        email:       Customer.normalize_email(draft.email), phone: draft.phone,
        group_name:  draft.group_name,
        from_date:   r[:from_date], to_date: r[:to_date],
        people:      [r[:value], 1].max, kind: "tente",
        status:      status, price_cents: prices[idx]
      )
      camping.save!
      stay.stay_items.create!(bookable: camping)
      camping
    end
  end

  # Persiste la grille van en N VanBooking (une par plage contiguë). Même
  # ventilation que le camping (poids `vehicles × nuits`).
  def persist_van_ranges!(stay:, draft:, status:, total_price_cents:)
    ranges  = van_night_ranges(draft)
    return [] if ranges.empty?
    prices  = distribute_cents(total_price_cents, ranges.map { |r| r[:value] * r[:nights] })
    ranges.each_with_index.map do |r, idx|
      van = VanBooking.new(
        firstname:   draft.first_name, lastname: draft.last_name,
        email:       Customer.normalize_email(draft.email), phone: draft.phone,
        group_name:  draft.group_name,
        from_date:   r[:from_date], to_date: r[:to_date],
        vehicles:    [r[:value], 1].max,
        status:      status, price_cents: prices[idx]
      )
      van.save!
      stay.stay_items.create!(bookable: van)
      van
    end
  end

  def persist_camping_booking!(stay:, draft:, status:, price_cents:)
    camping = build_camping_booking(draft: draft, status: status, price_cents: price_cents)
    camping.save!
    stay.stay_items.create!(bookable: camping)
    camping
  end

  def build_camping_booking(draft:, status:, price_cents:)
    CampingBooking.new(
      firstname:   draft.first_name,
      lastname:    draft.last_name,
      email:       Customer.normalize_email(draft.email),
      phone:       draft.phone,
      group_name:  draft.group_name,
      from_date:   draft.arrival_date,
      to_date:     draft.departure_date,
      people:      [draft_camping_peak_people(draft), 1].max,
      kind:        "tente",
      status:      status,
      price_cents: price_cents
    )
  end

  def persist_van_booking!(stay:, draft:, status:, price_cents:)
    van = build_van_booking(draft: draft, status: status, price_cents: price_cents)
    van.save!
    stay.stay_items.create!(bookable: van)
    van
  end

  def build_van_booking(draft:, status:, price_cents:)
    VanBooking.new(
      firstname:   draft.first_name,
      lastname:    draft.last_name,
      email:       Customer.normalize_email(draft.email),
      phone:       draft.phone,
      group_name:  draft.group_name,
      from_date:   draft.arrival_date,
      to_date:     draft.departure_date,
      vehicles:    [draft_van_peak_vehicles(draft), 1].max,
      status:      status,
      price_cents: price_cents
    )
  end

  # Réservables déjà rattachés au séjour (édition), ou nil.
  def existing_camping_booking(stay)
    stay.stay_items.where(bookable_type: "CampingBooking").first&.bookable
  end

  def existing_van_booking(stay)
    stay.stay_items.where(bookable_type: "VanBooking").first&.bookable
  end

  # TOUS les CampingBooking / VanBooking du séjour (une plage par nuit possible).
  def existing_camping_bookings(stay)
    stay.stay_items.where(bookable_type: "CampingBooking").filter_map(&:bookable)
  end

  def existing_van_bookings(stay)
    stay.stay_items.where(bookable_type: "VanBooking").filter_map(&:bookable)
  end

  # Détache + soft-delete tous les CampingBooking (resp. VanBooking) du séjour.
  # Utilisé à l'édition GRILLE : on reconstruit intégralement les plages (comme
  # `rebuild_reservations!` pour les chambres) plutôt que de réconcilier N↔N.
  def detach_camping_bookings!(stay)
    stay.stay_items.where(bookable_type: "CampingBooking").each do |item|
      item.bookable&.soft_delete!(validate: false)
      item.soft_delete!(validate: false)
    end
  end

  def detach_van_bookings!(stay)
    stay.stay_items.where(bookable_type: "VanBooking").each do |item|
      item.bookable&.soft_delete!(validate: false)
      item.soft_delete!(validate: false)
    end
  end

  def symbol(entry)
    entry.respond_to?(:symbolize_keys) ? entry.symbolize_keys : entry
  end
end
