# Composition TERRASSE d'un séjour depuis un `Reservations::Draft` (décision
# Michael, 2026-07-20). Concern PARTAGÉ par `Reservations::Builder` (création) et
# `Stays::AdminUpdater` (édition), sur le modèle de `MealComposition`.
#
# Décisions figées :
#   - La terrasse est réservée à des groupes qui occupent UNIQUEMENT la terrasse
#     (ex. randonneurs venant faire un BBQ) : forfait 2,50 €/pers/JOUR.
#   - ADMIN UNIQUEMENT — jamais proposé sur le funnel public /reservation.
#   - Sémantique = JOURS d'occupation. Un BBQ d'un jour = une ligne `{date, people}`
#     → un `CampingBooking` de `kind: "terrasse"`, `from = date`, `to = date + 1`
#     (convention `[from, to)` partagée avec Booking/Camping/Van) — donc l'existant
#     (calendrier, StayItem, totaux) fonctionne sans modification.
#   - La terrasse N'EST PAS une nuitée : elle ne déclenche pas l'emoji 💤 (cf.
#     `Calendar::DayStayBlocks::StayBlock#overnight?`).
#   - Le montant vient du barème B2C (`Pricing::Catalog::TERRACE_PER_PERSON_DAY_CENTS`)
#     — la même source que la ligne `:terrace` du devis, donc aucun double-compte.
module TerraceComposition
  extend ActiveSupport::Concern

  # `kind` du CampingBooking qui matérialise une terrasse (vs "tente" = camping).
  TERRACE_KIND = "terrasse".freeze

  private

  # Entrées terrasse exploitables du draft : [{ date: Date, people: Integer }].
  # Une ligne sans date OU sans personnes est écartée (saisie incomplète).
  def draft_terrace_entries(draft)
    Array(draft.terrasses).filter_map do |raw|
      entry  = raw.respond_to?(:symbolize_keys) ? raw.symbolize_keys : raw
      people = entry[:people].to_i
      date   = parse_terrace_date(entry[:date])
      next if people < 1 || date.nil?
      { date: date, people: people }
    end
  end

  def draft_has_terrace?(draft)
    draft_terrace_entries(draft).any?
  end

  # Prix TVAC d'une entrée terrasse (source unique = Catalog, comme `terrace_lines`).
  def terrace_entry_price_cents(entry)
    Pricing::Catalog::TERRACE_PER_PERSON_DAY_CENTS * entry[:people].to_i
  end

  # Persiste la terrasse en N CampingBooking `kind: "terrasse"` (un par JOUR).
  # Chacun couvre `[date, date + 1)` et porte son propre prix `people × 250` :
  # ∑ price_cents == `quote.terrace_cents` (invariant devis). Retourne les
  # CampingBooking créés.
  def persist_terrace_bookings!(stay:, draft:, status:)
    draft_terrace_entries(draft).map do |entry|
      camping = CampingBooking.new(
        firstname:   draft.first_name, lastname: draft.last_name,
        email:       Customer.normalize_email(draft.email), phone: draft.phone,
        group_name:  draft.group_name,
        from_date:   entry[:date], to_date: entry[:date] + 1,
        people:      entry[:people], kind: TERRACE_KIND,
        status:      status, price_cents: terrace_entry_price_cents(entry)
      )
      camping.save!
      stay.stay_items.create!(bookable: camping)
      camping
    end
  end

  # Tous les CampingBooking terrasse du séjour (une occupation par jour possible).
  def existing_terrace_bookings(stay)
    stay.stay_items
        .select { |i| i.bookable_type == "CampingBooking" }
        .filter_map(&:bookable)
        .select { |b| b.kind == TERRACE_KIND }
  end

  # Détache + soft-delete toutes les terrasses du séjour (rebuild à l'édition).
  def detach_terrace_bookings!(stay)
    stay.stay_items.where(bookable_type: "CampingBooking").each do |item|
      next unless item.bookable&.kind == TERRACE_KIND
      item.bookable&.soft_delete!(validate: false)
      item.soft_delete!(validate: false)
    end
  end

  # Réconcilie la terrasse à l'édition : rebuild complet (petit volume), comme les
  # repas. Les anciennes occupations sont soft-deleted, les nouvelles recréées.
  def reconcile_terrace!(stay, draft)
    detach_terrace_bookings!(stay)
    persist_terrace_bookings!(stay: stay, draft: draft, status: stay.status) if draft_has_terrace?(draft)
  end

  def parse_terrace_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
