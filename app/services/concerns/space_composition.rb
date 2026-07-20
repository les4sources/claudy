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
# MAPPING clé de pricing → `Space` (issue #75) : le funnel public price les
# espaces avec des clés forfaitaires (`grande_salle`, …) qui ne correspondent pas
# 1:1 aux `Space.name` en base (seed : « Tilleul », « Saule »). On résout en
# PRIORITÉ par le `Space.code` — identifiant STABLE et insensible au renommage
# d'affichage (seed : TIL/SAU/CUI) — puis, en repli tolérant, par une liste de
# noms candidats. Si aucune `Space` ne matche, la ligne reste dans le devis mais
# n'est PAS persistée : elle est alors remontée à l'admin (`unresolved_space_keys`
# / `unresolved_space_warning`) au lieu d'être perdue silencieusement.
module SpaceComposition
  extend ActiveSupport::Concern

  # Résolution PRIMAIRE : clé de pricing → `Space.code` (identifiant stable, seed
  # `db/seeds.rb`). Insensible au renommage d'affichage des `Space`.
  SPACE_CODES_BY_KEY = {
    "grande_salle" => "TIL",
    "petite_salle" => "SAU",
    "cuisine_pro"  => "CUI"
  }.freeze

  # Repli TOLÉRANT si aucun `code` ne matche : noms de `Space` acceptés par clé,
  # par ordre de préférence (le premier trouvé gagne). Cf. `PricingModel::SPACE_NAMES`.
  SPACE_NAMES_BY_KEY = {
    "grande_salle" => ["Grande Salle", "Tilleul"],
    "petite_salle" => ["Petite Salle", "Saule"],
    "cuisine_pro"  => ["Cuisine professionnelle", "Cuisine pro"]
  }.freeze

  # Libellés lisibles par clé, pour la remontée d'avertissement à l'admin.
  SPACE_LABELS_BY_KEY = {
    "grande_salle" => "Grande salle",
    "petite_salle" => "Petite salle",
    "cuisine_pro"  => "Cuisine professionnelle"
  }.freeze

  # Période de PRICING (funnel/admin : "journee"…) → durée CANONIQUE de
  # `SpaceReservation#duration` (vocabulaire tranche 1 : "day"/"evening"/
  # "fullday"/"2h"/"see_notes", celui que lit `SpaceBookingDecorator#duration`).
  # Sans ce mapping, la composition persistait "journee" → affiché « période
  # non précisée » partout (bug repéré le 2026-07-20). L'inverse vit dans
  # `Stays::DraftReconstructor` (édition → clés de pricing).
  DURATION_BY_PERIOD = {
    "journee"           => "day",
    "soiree"            => "evening",
    "journee_et_soiree" => "fullday"
  }.freeze
  PERIOD_BY_DURATION = DURATION_BY_PERIOD.invert.freeze

  private

  # Avertissement (String) listant les espaces DEVISÉS mais NON persistables
  # (aucune `Space` correspondante), ou nil si tout est résolu. Sert au contrôleur
  # admin à ne jamais perdre un espace en silence.
  def unresolved_space_warning(draft)
    keys = unresolved_space_keys(draft)
    return nil if keys.empty?

    labels = keys.map { |k| SPACE_LABELS_BY_KEY[k] || k }
    "Espace(s) non enregistrable(s) — aucune salle correspondante en base : " \
      "#{labels.join(', ')}. Ils figurent au devis mais N'ONT PAS été réservés " \
      "(vérifier le paramétrage des espaces)."
  end

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
  # `from/to_date` = les dates RÉELLEMENT occupées (min/max des specs) — pas la
  # fenêtre du séjour : une salle louée le seul 22 ne doit pas s'afficher
  # « du 21 au 23 » (bug repéré le 2026-07-20). Repli sur la fenêtre du draft
  # si les specs n'ont pas de dates (défensif).
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
      from_date:      dates.min || draft.arrival_date,
      to_date:        dates.max || draft.departure_date,
      status:         status,
      payment_status: "pending",
      price_cents:    price_cents
    )
    space_booking.generate_token
    assign_space_billing(space_booking, draft)
    specs.each do |spec|
      space_booking.space_reservations.build(space: spec[:space], date: spec[:date], duration: spec[:duration])
    end
    space_booking
  end

  # Facturation ESPACE (epic #81, Phase 6) : recopie les attributs de facturation
  # portés par le draft (`space_billing`) sur le SpaceBooking. No-op quand le draft
  # ne porte PAS la facturation (`space_billing` nil) — les valeurs existantes
  # SURVIVENT alors à une réédition qui ne les change pas. Les montants passent par
  # les setters `monetize` (`advance_amount=` / `deposit_amount=`) : conversion
  # €→cents IDENTIQUE au canal direct, et champ vide (nil) → cents nil, jamais 0.
  def assign_space_billing(space_booking, draft)
    billing = draft.space_billing
    return if billing.nil?

    space_booking.advance_amount = billing[:advance_amount]
    space_booking.deposit_amount = billing[:deposit_amount]
    space_booking.payment_method = billing[:payment_method]
    space_booking.event_id       = billing[:event_id]
    space_booking.arrival_time   = billing[:arrival_time]
    space_booking.departure_time = billing[:departure_time]
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
          entries << { key: key.to_s, date: arrival + night_idx, duration: canonical_duration(period) }
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
      entries << { key: key, date: date, duration: canonical_duration(period) }
    end

    entries
  end

  # Toujours persister le vocabulaire canonique ; une valeur déjà canonique
  # (réédition d'un séjour, donnée historique) passe inchangée.
  def canonical_duration(period)
    DURATION_BY_PERIOD.fetch(period.to_s, period.to_s)
  end

  def space_for_key(key)
    @space_by_key ||= {}
    return @space_by_key[key.to_s] if @space_by_key.key?(key.to_s)

    @space_by_key[key.to_s] = resolve_space_for_key(key.to_s)
  end

  # Résolution en deux temps : d'abord le `Space.code` stable (insensible au
  # renommage), sinon repli sur la liste de noms candidats.
  def resolve_space_for_key(key)
    if (code = SPACE_CODES_BY_KEY[key]).present?
      by_code = Space.find_by(code: code)
      return by_code if by_code
    end

    names = SPACE_NAMES_BY_KEY[key]
    names && Space.where(name: names).min_by { |s| names.index(s.name) || 99 }
  end

  def parse_space_date(value)
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
