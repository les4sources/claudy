namespace :payments do
  desc "Vérifie que 100 % des Payment portent un stay_id valide (vivant) — epic #26 Phase 4"
  task verify_stay_links: :environment do
    # On couvre TOUTE l'histoire (soft-deleted inclus), comme le backfill de la
    # Phase 3 : un paiement sans stay reste un trou d'invariant, actif ou non.
    total = Payment.with_deleted { Payment.unscoped.count }

    if total.zero?
      puts "=== Vérification liens Payment→Stay (epic #26, Phase 4) ==="
      puts "Aucun Payment en base — invariant trivialement respecté."
      puts "OK — 100 %."
      next
    end

    # « Valide » = stay_id présent ET pointant vers un Stay VIVANT. Le default
    # scope de Stay exclut les soft-deleted : `Stay.select(:id)` ne liste donc
    # que les stays vivants (même logique que bookings_without_live_stay).
    valid = Payment.with_deleted do
      Payment.unscoped.where(stay_id: Stay.select(:id)).count
    end
    invalid = total - valid
    percent = (valid.to_f / total * 100).round(2)

    puts "=== Vérification liens Payment→Stay (epic #26, Phase 4) ==="
    puts "Payments (deleted inclus)    : #{total}"
    puts "Avec stay_id vivant valide   : #{valid}"
    puts "Sans stay valide             : #{invalid}"
    puts "Couverture                   : #{percent} %"

    if invalid.positive?
      abort("ÉCHEC : #{invalid} Payment(s) sans stay_id valide. " \
            "Lancer `rake payments:backfill_stay_from_booking` puis re-vérifier.")
    end

    puts "OK — 100 % des Payment portent un stay_id valide."
  end

  desc "Rattache (idempotent) un stay_id aux Payment legacy via le Stay de leur booking — epic #26 Phase 4"
  task backfill_stay_from_booking: :environment do
    seen = 0
    linked = 0
    already = 0
    unresolved = 0

    # Le backfill de migration `AddStayToPayments` (2026-06-03) a posé stay_id
    # AVANT que la rake `stays:backfill_missing` (Phase 3, manuelle) ne crée les
    # Stays des bookings legacy : les paiements dont le Stay du booking est né
    # ensuite sont restés sans stay. On les rattrape ici. Idempotent : un paiement
    # déjà lié est sauté. Couvre les soft-deleted (l'invariant vaut pour tous).
    Payment.with_deleted do
      Payment.unscoped.find_each do |payment|
        seen += 1

        if payment.stay_id.present? && Stay.exists?(payment.stay_id)
          already += 1
          next
        end

        stay = payment.booking&.stay
        if stay.nil?
          # Ni stay direct, ni booking porteur d'un Stay vivant : anomalie réelle
          # à remonter (paiement orphelin), pas un plantage.
          unresolved += 1
          next
        end

        # `save!` volontaire : ce rattachement est une correction de donnée que
        # PaperTrail DOIT tracer (audit). Rétablit aussi booking_id si besoin.
        payment.update!(stay: stay)
        linked += 1
      end
    end

    puts "=== Backfill stay_id des Payment (epic #26, Phase 4) ==="
    puts "Payments vus                 : #{seen}"
    puts "Déjà liés (skip)             : #{already}"
    puts "Rattachés au Stay du booking : #{linked}"
    puts "Non résolus (à investiguer)  : #{unresolved}"
    if unresolved.positive?
      puts "⚠️  #{unresolved} paiement(s) sans stay ni booking porteur d'un Stay — à traiter à la main."
    else
      puts "OK — plus aucun Payment sans stay rattachable."
    end
  end

  desc "Passe en « Via Airbnb » les paiements des séjours Airbnb (DRY-RUN par défaut, APPLY=1 pour écrire)"
  task via_airbnb: :environment do
    apply = ENV["APPLY"] == "1"

    # Un séjour Airbnb = `Stay.airbnb` (Booking rattaché de plateforme airbnb,
    # ou client fourre-tout Airbnb). On y ajoute les paiements du canal booking
    # historique dont le Booking est Airbnb, au cas où leur stay_id manquerait.
    paiements = Payment.where(stay_id: Stay.airbnb.select(:id))
                       .or(Payment.where(booking_id: Booking.where(platform: "airbnb").select(:id)))
                       .includes(stay: :customer)
                       .order(:created_at)
                       .to_a

    deja = paiements.select { |p| p.payment_method == Payment::AIRBNB_METHOD }
    # Deux paiements gardent leur moyen : le miroir d'une Pizza Party payée sur
    # Tranches de Vie, et un vrai paiement Stripe (une activité réglée en ligne
    # par le client) — ceux-là ne sont pas passés par Airbnb.
    gardes = (paiements - deja).select { |p| p.tranchesdevie? || p.stripe_payment_intent_id.present? }
    a_changer = paiements - deja - gardes

    ligne = lambda do |p|
      sejour = p.stay ? "séjour ##{p.stay_id} #{p.stay.decorate.display_name}" : "booking ##{p.booking_id}"
      "  #{p.effective_date} · #{format('%.2f', p.amount_cents / 100.0)} € · #{p.payment_method || '—'} · #{p.status} · #{sejour}"
    end

    puts "=== Paiements des séjours Airbnb → « Via Airbnb » (#{apply ? 'APPLY' : 'DRY-RUN'}) ==="
    puts "Séjours Airbnb               : #{Stay.airbnb.count}"
    puts "Paiements trouvés            : #{paiements.size}"
    puts "Déjà « Via Airbnb »          : #{deja.size}"
    puts "Gardés (Stripe, Pizza Party) : #{gardes.size}"
    gardes.each { |p| puts ligne.(p) }
    puts "À passer en « Via Airbnb »   : #{a_changer.size} " \
         "(#{format('%.2f', a_changer.sum(&:amount_cents) / 100.0)} €)"
    a_changer.group_by(&:payment_method).each { |methode, lot| puts "  dont #{methode || '—'} : #{lot.size}" }
    a_changer.each { |p| puts ligne.(p) }

    unless apply
      puts "Rien n'est écrit. Relancer avec APPLY=1 pour appliquer."
      next
    end

    # PaperTrail trace chaque correction (moyen d'avant compris) ; sans
    # validation, pour qu'un vieux paiement du canal booking sans stay_id ne
    # bloque pas le lot — seul le moyen change.
    PaperTrail.request(whodunnit: "rake payments:via_airbnb") do
      Payment.transaction do
        a_changer.each do |p|
          p.payment_method = Payment::AIRBNB_METHOD
          p.save!(validate: false)
        end
      end
    end
    puts "OK — #{a_changer.size} paiement(s) passé(s) en « Via Airbnb »."
  end
end
