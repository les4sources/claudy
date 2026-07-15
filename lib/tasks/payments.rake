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
end
