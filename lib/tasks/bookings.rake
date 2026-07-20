namespace :bookings do
  # One-shot idempotente : convertit les réservations d'HÉBERGEMENT ne portant que
  # la chambre « Parking » (Room code "PKG", repli name "Parking" — le gîte
  # « Espace camping-cars ») en réservations de VAN / camping-car (VanBooking,
  # epic #66). Décision produit (vérifiée sur copie prod) : ces Booking étaient en
  # réalité des vans (1 véhicule, 15 €/nuit). On migre l'occupation vers le modèle
  # van en PRÉSERVANT le montant historique du séjour (on ne refacture pas le passé).
  #
  # DRY-RUN par défaut (rapport seul, aucune écriture persistée) ; APPLY=1 pour
  # appliquer. Même esprit que les rake one-shot du repo (cf. stays:backfill_missing,
  # claudy:reventilation:apply) : rapport ventilé avec les ids.
  #
  #   bundle exec rake bookings:convert_parking_to_van          # DRY-RUN
  #   APPLY=1 bundle exec rake bookings:convert_parking_to_van  # RÉEL
  #
  # Sémantique des DATES (nuits) : le Booking porte DÉJÀ la sémantique nuits
  # `[from_date, to_date)` (nights_count = to - from), et ses Reservation couvrent
  # `from...to` (une ligne par chambre × nuit, borne haute exclue). On copie donc
  # from_date/to_date TELS QUELS sur le VanBooking. On recalcule néanmoins les
  # bornes dérivées des Reservation (min ; max+1) et on RAPPORTE toute divergence
  # (date_divergence) — un garde-fou legacy, non bloquant.
  desc "Convertit les Booking 100 % chambre Parking (PKG) en VanBooking (1 véh., prix conservé). DRY-RUN sauf APPLY=1"
  task convert_parking_to_van: :environment do
    apply = ENV["APPLY"] == "1"

    # Chambre « Parking » : par code métier `PKG`, repli sur le nom « Parking ».
    # Résolue par code/nom (JAMAIS par id en dur).
    pkg_room_ids = Room.where(code: "PKG").pluck(:id)
    pkg_room_ids = Room.where(name: "Parking").pluck(:id) if pkg_room_ids.empty?

    report = {
      scanned: [],
      converted: [],
      skipped_mixed: [],
      skipped_empty: [],
      skipped_no_stay: [],
      failed_total_drift: [],
      date_divergence: [] # informatif (non bloquant)
    }

    if pkg_room_ids.empty?
      puts "=== bookings:convert_parking_to_van #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
      puts "Aucune chambre Parking (code PKG / name « Parking ») trouvée — rien à convertir."
      next
    end

    # CANDIDATS = Booking VIVANTS (default scope) portant au moins une Reservation
    # VIVANTE (Reservation a un default_scope soft-deletion) pointant la chambre
    # Parking. Un Booking sans AUCUNE réservation Parking est hors périmètre
    # (jamais scanné, jamais rapporté). Idempotence : une fois converti, le Booking
    # est soft-deleté et ses Reservation soft-deletées en cascade → il ne ressort
    # plus comme candidat.
    candidate_ids = Reservation.where(room_id: pkg_room_ids).distinct.pluck(:booking_id)

    Booking.where(id: candidate_ids).find_each do |booking|
      report[:scanned] << booking.id

      living_reservations = booking.reservations.to_a # default scope = vivantes

      # Filet de sécurité (course entre le pluck et l'itération) : plus aucune
      # réservation vivante → rien à convertir.
      if living_reservations.empty?
        report[:skipped_empty] << booking.id
        next
      end

      # Mixte : au moins une réservation vivante pointe une AUTRE chambre que le
      # Parking → on ne touche pas (le van n'agrège qu'un séjour 100 % parking).
      unless living_reservations.all? { |r| pkg_room_ids.include?(r.room_id) }
        report[:skipped_mixed] << booking.id
        next
      end

      # 100 % Parking mais sans Stay rattaché : ne devrait plus exister depuis le
      # backfill (tout Booking a un Stay). On ne touche pas.
      stay = booking.stay
      if stay.nil?
        report[:skipped_no_stay] << booking.id
        next
      end

      # Garde-fou legacy : les bornes du Booking doivent coïncider avec celles
      # dérivées des Reservation (min ; max+1). Divergence rapportée, non bloquante.
      res_dates = living_reservations.map(&:date).compact
      if res_dates.any?
        derived_from = res_dates.min
        derived_to   = res_dates.max + 1
        if derived_from != booking.from_date || derived_to != booking.to_date
          report[:date_divergence] <<
            "booking #{booking.id} : booking [#{booking.from_date}..#{booking.to_date}) vs réservations [#{derived_from}..#{derived_to})"
        end
      end

      total_before = stay.total_amount_cents
      outcome = nil

      # Transaction PAR Booking : tout-ou-rien local. En DRY-RUN, on exécute
      # réellement la conversion (pour valider qu'elle passe ET détecter une
      # dérive de total) puis on rollback systématiquement — zéro écriture
      # persistée. En APPLY, on commit sauf dérive de total.
      #
      # `requires_new: true` est INDISPENSABLE : sans lui, un `raise
      # ActiveRecord::Rollback` imbriqué dans une transaction parente (fixtures
      # transactionnelles des specs, ou tout appelant déjà en transaction) serait
      # silencieusement avalé SANS rien annuler — le DRY-RUN écrirait alors pour
      # de vrai. Le savepoint garantit un rollback réel dans tous les cas.
      ActiveRecord::Base.transaction(requires_new: true) do
        van = VanBooking.new(
          firstname: booking.firstname,
          lastname: booking.lastname,
          email: booking.email,
          phone: booking.phone,
          group_name: booking.group_name,
          status: booking.status,
          vehicles: 1,
          # Le Booking porte déjà la sémantique nuits [from, to) → copie directe.
          from_date: booking.from_date,
          to_date: booking.to_date,
          # INVARIANT : le montant du séjour ne change pas. On conserve le
          # price_cents historique tel quel (on ne refacture pas le passé au
          # barème van courant).
          price_cents: booking.price_cents
        )
        van.notes = booking.notes if van.respond_to?(:notes) && booking.respond_to?(:notes)
        # payment_status : VanBooking ne porte PAS cette colonne (le statut de
        # paiement vit au niveau du Stay, préservé) — on ne le copie que si un
        # jour le modèle l'acquiert.
        if VanBooking.column_names.include?("payment_status") && booking.respond_to?(:payment_status)
          van.payment_status = booking.payment_status
        end
        van.save!

        # Rattache le van au MÊME séjour.
        StayItem.create!(stay: stay, bookable: van)

        # Retire le StayItem du Booking (StayItem porte has_soft_deletion →
        # soft-delete), puis soft-delete le Booking. Le soft-delete du Booking
        # cascade sur ses Reservation (dependent: :destroy + Reservation
        # soft-deletable → soft_delete_dependents) : les chambres sont rendues au
        # calendrier et au veto de dispo. Même pattern que Stays::DestroyService.
        StayItem.find_by(bookable: booking)&.soft_delete!(validate: false)
        booking.soft_delete!(validate: false)

        # Recalcule les agrégats du séjour sur une association fraîche, puis
        # vérifie l'invariant : le total du séjour est INCHANGÉ.
        stay.reload
        stay.recompute_aggregates!

        if stay.total_amount_cents != total_before
          outcome = :drift
          raise ActiveRecord::Rollback
        end

        outcome = :converted
        # DRY-RUN : on annule toutes les écritures.
        raise ActiveRecord::Rollback unless apply
      end

      case outcome
      when :converted then report[:converted] << booking.id
      when :drift     then report[:failed_total_drift] << booking.id
      end
    end

    print_parking_van_report(report, apply)
    abort("ÉCHEC : #{report[:failed_total_drift].size} séjour(s) en dérive de total.") if report[:failed_total_drift].any?
  end
end

def print_parking_van_report(report, apply)
  puts "=== bookings:convert_parking_to_van #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
  puts "Scannés (candidats Parking)  : #{report[:scanned].size} #{parking_ids(report[:scanned])}"
  puts "Convertis en van             : #{report[:converted].size} #{parking_ids(report[:converted])}"
  puts "Ignorés — mixtes (PKG+autre) : #{report[:skipped_mixed].size} #{parking_ids(report[:skipped_mixed])}"
  puts "Ignorés — sans réservation   : #{report[:skipped_empty].size} #{parking_ids(report[:skipped_empty])}"
  puts "Ignorés — sans séjour        : #{report[:skipped_no_stay].size} #{parking_ids(report[:skipped_no_stay])}"
  puts "Échecs — dérive de total     : #{report[:failed_total_drift].size} #{parking_ids(report[:failed_total_drift])}"
  unless report[:date_divergence].empty?
    puts "Divergences de dates (info)  : #{report[:date_divergence].size}"
    report[:date_divergence].each { |line| puts "  - #{line}" }
  end
  puts(apply ? "OK — conversions appliquées." : "DRY-RUN — aucune écriture. Relancer avec APPLY=1 pour appliquer.")
end

def parking_ids(list)
  list.empty? ? "" : "→ #{list.sort.join(', ')}"
end
