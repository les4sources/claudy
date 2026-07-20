# « Laurier (mezzanine) » (2026-07-20) : la chambre doit appartenir à La
# Hulotte ET au Grand-Duc — réserver l'un de ces gîtes doit l'occuper. Elle
# n'était liée à aucun hébergement (donc toujours « libre »). La task :
#   1. lie la chambre aux deux gîtes (idempotent) ;
#   2. rattrape les Booking VIVANTS pleine-maison de ces gîtes : pour chaque
#      nuit où le booking occupe TOUTES les autres chambres du gîte, ajoute la
#      Reservation Laurier manquante (les bookings « chambres seules » — sous-
#      ensemble — ne sont pas touchés).
# Dry-run par défaut ; APPLY=1 pour appliquer. `rake rooms:link_laurier`.
namespace :rooms do
  desc "Lie Laurier (mezzanine) à La Hulotte + Le Grand-Duc et rattrape les réservations (dry-run par défaut, APPLY=1)"
  task link_laurier: :environment do
    apply = ENV["APPLY"] == "1"
    room = Room.unscoped.where("name ILIKE ?", "%laurier%").first or abort "Chambre Laurier introuvable."
    lodgings = Lodging.where(name: ["La Hulotte", "Le Grand-Duc"]).to_a
    abort "Gîtes introuvables." if lodgings.size < 2

    puts "=== rooms:link_laurier (#{apply ? "RÉEL" : "DRY-RUN"}) ==="
    lodgings.each do |lodging|
      if lodging.rooms.include?(room)
        puts "#{lodging.name} : déjà liée"
      else
        lodging.rooms << room if apply
        puts "#{lodging.name} : liaison #{apply ? "créée" : "à créer"}"
      end
    end

    created = 0
    lodgings.each do |lodging|
      other_room_ids = lodging.rooms.where.not(id: room.id).pluck(:id)
      next if other_room_ids.empty?
      Booking.where(lodging_id: lodging.id).find_each do |booking|
        nights = Reservation.where(booking_id: booking.id).group_by(&:date)
        nights.each do |date, reservations|
          rooms_that_night = reservations.map(&:room_id).uniq
          # Pleine maison cette nuit = toutes les autres chambres occupées,
          # Laurier absente → on la complète.
          next unless (other_room_ids - rooms_that_night).empty?
          next if rooms_that_night.include?(room.id)
          Reservation.create!(booking: booking, room: room, date: date) if apply
          created += 1
          puts "  + Laurier le #{date} (booking ##{booking.id}, #{lodging.name})"
        end
      end
    end
    puts "Réservations Laurier #{apply ? "créées" : "à créer"} : #{created}"
    puts apply ? "OK — appliqué." : "DRY-RUN — rien écrit. APPLY=1 pour appliquer."
  end
end
