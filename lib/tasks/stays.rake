namespace :stays do
  desc "Rattache un Stay à tout Booking ET SpaceBooking qui n'en a pas (idempotent) — epic #26 Phase 3, epic #81 Phase 1"
  task backfill_missing: :environment do
    # --- Bookings (epic #26, Phase 3) -------------------------------------
    created = 0
    skipped = 0
    seen = 0

    # On couvre TOUTE l'histoire (actifs, passés, annulés ET soft-deleted), comme
    # la migration legacy : `with_deleted` relâche le seul default scope de Booking.
    # Stay/StayItem gardent leur scope vivant, donc `booking.stay` reste la clé
    # d'idempotence (un booking déjà rattaché est sauté).
    Booking.with_deleted do
      Booking.unscoped.find_each do |booking|
        seen += 1
        if booking.stay.present?
          skipped += 1
          next
        end
        Stays::EnsureForBooking.call(booking)
        created += 1
      end
    end

    remaining = bookings_without_live_stay

    puts "=== Backfill stays — Bookings (epic #26, Phase 3) ==="
    puts "Bookings vus                 : #{seen}"
    puts "Déjà rattachés (skip)        : #{skipped}"
    puts "Stays créés                  : #{created}"
    puts "Bookings encore sans Stay    : #{remaining}"
    abort("ÉCHEC : #{remaining} booking(s) sans Stay après backfill.") if remaining.positive?
    puts "OK — 0 Booking sans Stay."

    # --- SpaceBookings (epic #81, Phase 1) --------------------------------
    # On ne couvre QUE les SpaceBooking vivants : un SpaceBooking soft-deleted
    # n'ancre aucun Stay (cf. Stays::EnsureForSpaceBooking, qui renvoie nil pour
    # un enregistrement supprimé). Le default scope de SpaceBooking les exclut
    # donc naturellement du find_each comme du compteur.
    sb_created = 0
    sb_skipped = 0
    sb_seen = 0
    sb_before = space_bookings_without_live_stay

    SpaceBooking.find_each do |space_booking|
      sb_seen += 1
      if space_booking.stay.present?
        sb_skipped += 1
        next
      end
      Stays::EnsureForSpaceBooking.call(space_booking)
      sb_created += 1
    end

    sb_after = space_bookings_without_live_stay

    puts ""
    puts "=== Backfill stays — SpaceBookings (epic #81, Phase 1) ==="
    puts "SpaceBookings vus                 : #{sb_seen}"
    puts "Déjà rattachés (skip)             : #{sb_skipped}"
    puts "Stays créés                       : #{sb_created}"
    puts "SpaceBookings sans Stay (avant)   : #{sb_before}"
    puts "SpaceBookings sans Stay (après)   : #{sb_after}"
    abort("ÉCHEC : #{sb_after} space_booking(s) sans Stay après backfill.") if sb_after.positive?
    puts "OK — 0 SpaceBooking sans Stay."
  end
end

# Compte les Bookings (deleted inclus) dépourvus d'un Stay VIVANT. « Rattaché » =
# StayItem vivant pointant vers un Stay vivant — exactement la même définition que
# booking.stay et que Stays::EnsureForBooking#live_stay_for, sinon skip et count
# divergent dans le cas latent « StayItem vivant → Stay soft-deleted ».
# On restreint aux stay_id vivants via le default scope de Stay : `joins(:stay)`
# n'applique PAS le default scope de la table jointe (il compterait les Stays
# soft-deleted), d'où le sous-select explicite `stay_id: Stay.select(:id)`.
def bookings_without_live_stay
  linked_ids = StayItem
    .where(bookable_type: "Booking", stay_id: Stay.select(:id))
    .pluck(:bookable_id)
  Booking.with_deleted do
    Booking.unscoped.where.not(id: linked_ids).count
  end
end

# Compte les SpaceBooking VIVANTS dépourvus d'un Stay VIVANT. Même définition
# d'« orphelin » que Stays::EnsureForSpaceBooking#live_stay_for et que
# space_booking.stay : StayItem vivant pointant vers un Stay vivant. On borne aux
# SpaceBooking vivants (default scope) et aux stay_id vivants (sous-select
# explicite `Stay.select(:id)`, car `joins(:stay)` n'appliquerait pas le default
# scope de la table jointe et compterait les Stays soft-deleted).
def space_bookings_without_live_stay
  linked_ids = StayItem
    .where(bookable_type: "SpaceBooking", stay_id: Stay.select(:id))
    .pluck(:bookable_id)
  SpaceBooking.where.not(id: linked_ids).count
end

namespace :stays do
  desc "Rapatrie les notes des réservations d'origine dans la note du séjour (idempotent) — Michael 2026-08-24"
  task merge_origin_notes: :environment do
    apply = ENV["APPLY"] == "1"
    seen = 0
    changed = []

    # Tous les séjours, y compris soft-deleted : une fiche restaurée doit porter
    # la même note unique que les autres. `stay_items` reste sur son scope vivant.
    Stay.with_deleted do
      Stay.unscoped.includes(stay_items: :bookable).find_each do |stay|
        seen += 1
        avant = stay.notes.to_s
        apres = Stays::MergeOriginNotes.merged_text(stay)
        next if apres == avant

        changed << stay.id
        Stays::MergeOriginNotes.call(stay) if apply
      end
    end

    puts "Séjours parcourus : #{seen}"
    puts "Notes à rapatrier  : #{changed.size}"
    puts "Ids                : #{changed.first(50).join(', ')}#{changed.size > 50 ? '…' : ''}" if changed.any?
    puts apply ? "APPLIQUÉ." : "DRY-RUN — relancer avec APPLY=1 pour écrire."
  end
end
