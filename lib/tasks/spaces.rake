namespace :spaces do
  # One-shot idempotente : convertit les réservations d'espace « Parking » (PKG)
  # en réservations de VAN / camping-car (VanBooking, epic #66). Décision produit :
  # toute réservation d'espace ne portant QUE l'espace Parking était en réalité un
  # van (1 véhicule, 15 €/nuit). On migre donc l'occupation vers le modèle van, en
  # PRÉSERVANT le montant historique du séjour (on ne refacture jamais le passé).
  #
  # DRY-RUN par défaut (rapport seul, aucune écriture persistée) ; APPLY=1 pour
  # appliquer. Même esprit que les rake one-shot du repo (cf. stays:backfill_missing,
  # claudy:reventilation:apply) : rapport ventilé avec les ids.
  #
  #   bundle exec rake spaces:convert_parking_to_van          # DRY-RUN
  #   APPLY=1 bundle exec rake spaces:convert_parking_to_van  # RÉEL
  #
  # Sémantique des DATES (nuits) : une SpaceReservation porte une DATE (un jour de
  # parking réservé). Le VanBooking, lui, raisonne en NUITS `[from, to)`. Chaque
  # jour de parking réservé = une nuit de van. D'où :
  #   from_date = min(dates des réservations)
  #   to_date   = max(dates des réservations) + 1 jour
  # (2 jours consécutifs de parking → [J, J+2) = 2 nuits).
  desc "Convertit les SpaceBooking 100 % Parking (PKG) en VanBooking (1 véh., prix conservé). DRY-RUN sauf APPLY=1"
  task convert_parking_to_van: :environment do
    apply = ENV["APPLY"] == "1"

    # Espace « Parking » : par code métier `PKG`, repli sur le nom « Parking ».
    pkg_space_ids = Space.where(code: "PKG").pluck(:id)
    pkg_space_ids = Space.where(name: "Parking").pluck(:id) if pkg_space_ids.empty?

    report = {
      scanned: [],
      converted: [],
      skipped_mixed: [],
      skipped_empty: [],
      skipped_no_stay: [],
      failed_total_drift: []
    }

    if pkg_space_ids.empty?
      puts "=== spaces:convert_parking_to_van #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
      puts "Aucun espace Parking (code PKG / name « Parking ») trouvé — rien à convertir."
      next
    end

    # CANDIDATS = SpaceBooking VIVANTS (default scope) portant au moins une
    # SpaceReservation VIVANTE (deleted_at IS NULL — ce modèle n'a pas de
    # soft-deletion, on filtre donc la colonne à la main) pointant vers un espace
    # Parking. Un SpaceBooking sans AUCUNE réservation Parking est hors périmètre
    # (jamais scanné, jamais rapporté). Idempotence : une fois converti, ses
    # réservations sont détruites → il ne ressort plus comme candidat.
    candidate_ids = SpaceReservation
      .where(deleted_at: nil, space_id: pkg_space_ids)
      .distinct
      .pluck(:space_booking_id)

    SpaceBooking.where(id: candidate_ids).find_each do |space_booking|
      report[:scanned] << space_booking.id

      living_reservations = space_booking.space_reservations.where(deleted_at: nil).to_a

      # Filet de sécurité (course entre le pluck et l'itération) : plus aucune
      # réservation vivante → rien à convertir.
      if living_reservations.empty?
        report[:skipped_empty] << space_booking.id
        next
      end

      # Mixte : au moins une réservation vivante pointe un AUTRE espace que le
      # Parking → on ne touche pas (le van n'agrège qu'un séjour 100 % parking).
      unless living_reservations.all? { |r| pkg_space_ids.include?(r.space_id) }
        report[:skipped_mixed] << space_booking.id
        next
      end

      # 100 % Parking mais sans Stay rattaché : ne devrait plus exister depuis le
      # backfill (tout SpaceBooking a un Stay). On ne touche pas.
      stay = space_booking.stay
      if stay.nil?
        report[:skipped_no_stay] << space_booking.id
        next
      end

      total_before = stay.total_amount_cents
      outcome = nil

      # Transaction PAR SpaceBooking : tout-ou-rien local. En DRY-RUN, on exécute
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
        dates = living_reservations.map(&:date).compact
        from_date = dates.min
        to_date   = dates.max + 1 # sémantique nuits [from, to)

        van = VanBooking.new(
          firstname: space_booking.firstname,
          lastname: space_booking.lastname,
          email: space_booking.email,
          phone: space_booking.phone,
          group_name: space_booking.group_name,
          status: space_booking.status,
          vehicles: 1,
          from_date: from_date,
          to_date: to_date,
          # INVARIANT : le montant du séjour ne change pas. On conserve le
          # price_cents historique tel quel (on ne refacture pas le passé au
          # barème van courant).
          price_cents: space_booking.price_cents
        )
        van.notes = space_booking.notes if van.respond_to?(:notes) && space_booking.respond_to?(:notes)
        # payment_status : VanBooking ne porte PAS cette colonne (le statut de
        # paiement vit au niveau du Stay, préservé) — on ne le copie que si un
        # jour le modèle l'acquiert.
        if VanBooking.column_names.include?("payment_status") && space_booking.respond_to?(:payment_status)
          van.payment_status = space_booking.payment_status
        end
        van.save!

        # Rattache le van au MÊME séjour.
        StayItem.create!(stay: stay, bookable: van)

        # SpaceReservation n'est pas soft-deletable et ne cascade pas depuis le
        # SpaceBooking : on retire ses lignes explicitement (même pattern que
        # Stays::DestroyService). Rend l'occupation/veto de l'espace Parking.
        space_booking.space_reservations.destroy_all

        # Retire le StayItem du SpaceBooking (StayItem porte has_soft_deletion →
        # soft-delete) puis soft-delete le SpaceBooking lui-même.
        item = StayItem.find_by(bookable: space_booking)
        item&.soft_delete!(validate: false)
        space_booking.soft_delete!(validate: false)

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
      when :converted then report[:converted] << space_booking.id
      when :drift     then report[:failed_total_drift] << space_booking.id
      end
    end

    print_report(report, apply)
    abort("ÉCHEC : #{report[:failed_total_drift].size} séjour(s) en dérive de total.") if report[:failed_total_drift].any?
  end
end

def print_report(report, apply)
  puts "=== spaces:convert_parking_to_van #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
  puts "Scannés (candidats Parking)  : #{report[:scanned].size} #{ids(report[:scanned])}"
  puts "Convertis en van             : #{report[:converted].size} #{ids(report[:converted])}"
  puts "Ignorés — mixtes (PKG+autre) : #{report[:skipped_mixed].size} #{ids(report[:skipped_mixed])}"
  puts "Ignorés — sans réservation   : #{report[:skipped_empty].size} #{ids(report[:skipped_empty])}"
  puts "Ignorés — sans séjour        : #{report[:skipped_no_stay].size} #{ids(report[:skipped_no_stay])}"
  puts "Échecs — dérive de total     : #{report[:failed_total_drift].size} #{ids(report[:failed_total_drift])}"
  puts(apply ? "OK — conversions appliquées." : "DRY-RUN — aucune écriture. Relancer avec APPLY=1 pour appliquer.")
end

def ids(list)
  list.empty? ? "" : "→ #{list.sort.join(', ')}"
end
