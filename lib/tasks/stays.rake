namespace :stays do
  desc "Rattache un Stay à tout Booking qui n'en a pas (idempotent) — epic #26 Phase 3"
  task backfill_missing: :environment do
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

    puts "=== Backfill stays (epic #26, Phase 3) ==="
    puts "Bookings vus                 : #{seen}"
    puts "Déjà rattachés (skip)        : #{skipped}"
    puts "Stays créés                  : #{created}"
    puts "Bookings encore sans Stay    : #{remaining}"
    abort("ÉCHEC : #{remaining} booking(s) sans Stay après backfill.") if remaining.positive?
    puts "OK — 0 Booking sans Stay."
  end
end

# Compte les Bookings (deleted inclus) dépourvus d'un StayItem vivant. Passe par
# les StayItem vivants pour n'exclure QUE les rattachements actifs, cohérent avec
# la clé d'idempotence booking.stay.
def bookings_without_live_stay
  linked_ids = StayItem.where(bookable_type: "Booking").pluck(:bookable_id)
  Booking.with_deleted do
    Booking.unscoped.where.not(id: linked_ids).count
  end
end
