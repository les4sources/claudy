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

  # Nombre de véhicules demandés — une entrée `vans` = un véhicule (contrat
  # PricingModel : `van_lines` produit une ligne par entrée).
  def draft_van_vehicles(draft)
    Array(draft.vans).count { |e| (symbol(e)[:nights] || draft.nights).to_i.positive? }
  end

  def draft_has_van?(draft)
    draft_van_vehicles(draft).positive?
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

  # --- Persistance ---------------------------------------------------------

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
      people:      [draft_camping_people(draft), 1].max,
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
      vehicles:    [draft_van_vehicles(draft), 1].max,
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

  def symbol(entry)
    entry.respond_to?(:symbolize_keys) ? entry.symbolize_keys : entry
  end
end
