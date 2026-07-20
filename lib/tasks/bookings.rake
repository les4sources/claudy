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

  # One-shot idempotente : convertit les réservations d'ESPACE « tentes » (Bois,
  # Pâture ouest, Pâture est) en réservations de CAMPING (CampingBooking kind
  # "tente", epic #66). Décision Michael : toute résa de ces espaces était en
  # réalité un camping tente ; le nombre de PERSONNES se DÉDUIT du prix
  # (people = prix / (nuits × 7,50 €/pers/nuit)). On PRÉSERVE le montant du séjour
  # (on ne refacture pas le passé). Sœur de convert_parking_to_van (même famille).
  #
  # DRY-RUN par défaut (rapport seul, aucune écriture) ; APPLY=1 pour appliquer.
  #
  #   bundle exec rake bookings:convert_tent_spaces_to_camping          # DRY-RUN
  #   APPLY=1 bundle exec rake bookings:convert_tent_spaces_to_camping  # RÉEL
  #
  # Sémantique nuits : une SpaceReservation porte une DATE (un jour réservé).
  # from_date = min(dates), to_date = max(dates) + 1 ([from, to)) ; nuits = nombre
  # de dates réservées DISTINCTES. `people` se déduit du prix conservé :
  #   people = price_cents / (nuits × 750)
  # Si la division ne tombe PAS juste (reste ≠ 0) ou donne 0 → on NE convertit PAS
  # (skipped_price_ambiguous, avec le détail) : Michael tranche à la main.
  desc "Convertit les SpaceBooking 100 % espaces tentes (Bois/Pâtures) en CampingBooking tente (people déduit du prix). DRY-RUN sauf APPLY=1"
  task convert_tent_spaces_to_camping: :environment do
    apply = ENV["APPLY"] == "1"
    rate = Pricing::Catalog::CAMPING_PER_PERSON_NIGHT_CENTS.fetch("tente") # 750 cts

    # Espaces « tentes » : Bois + pâtures, résolus par CODE ou NOM (jamais par id
    # en dur). Codes prod : "Bois", "OUEST", "EST" ; noms : "Bois", "Pature ouest",
    # "Pature est". Regex insensible à la casse et à l'accent de « pâture ».
    tent_space_ids = Space.where(
      "code ~* :codes OR name ~* :names",
      codes: '^(bois|ouest|est)$',
      names: 'bois|p[aâ]ture'
    ).pluck(:id)

    report = {
      scanned: [],
      converted: [],
      skipped_mixed: [],
      skipped_empty: [],
      skipped_no_stay: [],
      skipped_price_ambiguous: [],
      failed_total_drift: []
    }

    if tent_space_ids.empty?
      puts "=== bookings:convert_tent_spaces_to_camping #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
      puts "Aucun espace tente (Bois / Pâture ouest / Pâture est) trouvé — rien à convertir."
      next
    end

    # CANDIDATS = SpaceBooking VIVANTS portant ≥1 SpaceReservation VIVANTE
    # (deleted_at IS NULL — ce modèle n'a pas de soft-deletion, on filtre la
    # colonne) pointant un espace tente. Idempotence : après conversion les
    # réservations sont détruites → plus candidat.
    candidate_ids = SpaceReservation
      .where(deleted_at: nil, space_id: tent_space_ids)
      .distinct
      .pluck(:space_booking_id)

    SpaceBooking.where(id: candidate_ids).find_each do |space_booking|
      report[:scanned] << space_booking.id

      living_reservations = space_booking.space_reservations.where(deleted_at: nil).to_a

      if living_reservations.empty?
        report[:skipped_empty] << space_booking.id
        next
      end

      # Mixte : au moins une réservation vivante pointe un espace NON tente (une
      # salle) → on ne touche pas.
      unless living_reservations.all? { |r| tent_space_ids.include?(r.space_id) }
        report[:skipped_mixed] << space_booking.id
        next
      end

      stay = space_booking.stay
      if stay.nil?
        report[:skipped_no_stay] << space_booking.id
        next
      end

      # `people` déduit du prix : nuits = nombre de dates DISTINCTES réservées.
      dates = living_reservations.map(&:date).compact.uniq
      nights = dates.size
      price_cents = space_booking.price_cents
      denom = nights * rate

      if price_cents.nil? || denom.zero?
        report[:skipped_price_ambiguous] <<
          "space_booking #{space_booking.id} : prix=#{price_cents.inspect}, nuits=#{nights} (indéterminable)"
        next
      end

      people, remainder = price_cents.divmod(denom)
      # La division DOIT tomber juste (reste 0) et donner ≥1 personne, sinon on ne
      # devine pas : Michael tranchera (people ≥ 1 est aussi la validation modèle).
      if remainder != 0 || people <= 0
        report[:skipped_price_ambiguous] <<
          "space_booking #{space_booking.id} : prix=#{price_cents} cts, nuits=#{nights}, #{price_cents}/#{denom}=#{(price_cents.to_f / denom).round(2)} pers (non entier)"
        next
      end

      total_before = stay.total_amount_cents
      outcome = nil

      # Transaction PAR SpaceBooking, `requires_new: true` (rollback réel du
      # DRY-RUN et sous fixtures transactionnelles — cf. convert_parking_to_van).
      ActiveRecord::Base.transaction(requires_new: true) do
        from_date = dates.min
        to_date   = dates.max + 1 # sémantique nuits [from, to)

        camping = CampingBooking.new(
          firstname: space_booking.firstname,
          lastname: space_booking.lastname,
          email: space_booking.email,
          phone: space_booking.phone,
          group_name: space_booking.group_name,
          status: space_booking.status,
          kind: "tente",
          people: people,
          from_date: from_date,
          to_date: to_date,
          # INVARIANT : le montant du séjour ne change pas — prix conservé tel quel.
          price_cents: price_cents
        )
        camping.notes = space_booking.notes if camping.respond_to?(:notes) && space_booking.respond_to?(:notes)
        camping.save!

        StayItem.create!(stay: stay, bookable: camping)

        # SpaceReservation : pas de soft-deletion et pas de cascade depuis le
        # SpaceBooking → on retire les lignes explicitement (pattern
        # Stays::DestroyService). Rend l'occupation/veto des espaces tentes.
        space_booking.space_reservations.destroy_all
        StayItem.find_by(bookable: space_booking)&.soft_delete!(validate: false)
        space_booking.soft_delete!(validate: false)

        stay.reload
        stay.recompute_aggregates!

        if stay.total_amount_cents != total_before
          outcome = :drift
          raise ActiveRecord::Rollback
        end

        outcome = :converted
        raise ActiveRecord::Rollback unless apply # DRY-RUN : on annule tout
      end

      case outcome
      when :converted then report[:converted] << space_booking.id
      when :drift     then report[:failed_total_drift] << space_booking.id
      end
    end

    print_tent_camping_report(report, apply)
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

def print_tent_camping_report(report, apply)
  puts "=== bookings:convert_tent_spaces_to_camping #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
  puts "Scannés (candidats tentes)         : #{report[:scanned].size} #{parking_ids(report[:scanned])}"
  puts "Convertis en camping (tente)       : #{report[:converted].size} #{parking_ids(report[:converted])}"
  puts "Ignorés — mixtes (tente + salle)   : #{report[:skipped_mixed].size} #{parking_ids(report[:skipped_mixed])}"
  puts "Ignorés — sans réservation         : #{report[:skipped_empty].size} #{parking_ids(report[:skipped_empty])}"
  puts "Ignorés — sans séjour              : #{report[:skipped_no_stay].size} #{parking_ids(report[:skipped_no_stay])}"
  puts "Échecs — dérive de total           : #{report[:failed_total_drift].size} #{parking_ids(report[:failed_total_drift])}"
  unless report[:skipped_price_ambiguous].empty?
    puts "Ignorés — prix ambigu (à trancher) : #{report[:skipped_price_ambiguous].size}"
    report[:skipped_price_ambiguous].each { |line| puts "  - #{line}" }
  end
  puts(apply ? "OK — conversions appliquées." : "DRY-RUN — aucune écriture. Relancer avec APPLY=1 pour appliquer.")
end
