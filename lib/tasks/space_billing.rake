namespace :space_bookings do
  # One-shot idempotente : transforme les DONNÉES DE FACTURATION portées par les
  # SpaceBooking (colonnes `*_amount_cents`, `payment_method`, `payment_status`)
  # en Payment rattachés au Stay du séjour. Objectif : retrouver sur la fiche
  # séjour TOUS les paiements (effectués ET en attente) d'un séjour « espaces ».
  #
  # DRY-RUN par défaut (rapport seul, ZÉRO écriture) ; APPLY=1 pour appliquer.
  # Même esprit que `bookings:convert_parking_to_van` : transaction PAR
  # SpaceBooking avec `requires_new: true` (savepoint) — indispensable pour que le
  # DRY-RUN annule RÉELLEMENT ses écritures même imbriqué dans les fixtures
  # transactionnelles des specs.
  #
  #   bundle exec rake space_bookings:billing_to_payments          # DRY-RUN
  #   APPLY=1 bundle exec rake space_bookings:billing_to_payments  # RÉEL
  #
  # ─── SÉMANTIQUE des champs de facturation d'un SpaceBooking (vérifiée sur la
  #     page publique `/espaces/:token` + locales `public.space_bookings.*`) ───
  #
  #   • price_cents          : montant TOTAL dû pour la réservation d'espace.
  #                            (« Montant » ; 0 ⇒ « Offert »).
  #   • paid_amount_cents    : montant RÉELLEMENT REÇU à ce jour (« Nous avons
  #                            reçu un paiement pour un montant de X »).
  #   • payment_status       : "paid" (reçu en intégralité) / "partially_paid" /
  #                            (pending/nil = rien reçu).
  #   • advance_amount_cents : ACOMPTE DEMANDÉ (« Merci de régler votre acompte de
  #                            X ») — une CONSIGNE de paiement, PAS un encaissement
  #                            ni le total dû. Volontairement NON utilisé comme
  #                            montant du Payment pending : le vrai « attendu non
  #                            encaissé » est le SOLDE (price − reçu), sinon on
  #                            sous-estimerait la dette du séjour.
  #   • deposit_amount_cents : CAUTION (« Votre caution: X ») — dépôt de garantie
  #                            remboursable. Ce N'EST PAS un paiement de séjour :
  #                            on ne crée RIEN, on le liste seulement (info).
  #
  # ─── RÈGLES de transformation ───
  #
  #   received = payment_status == "paid" ? (price>0 ? price : paid_amount)
  #                                       : paid_amount
  #   outstanding = price − received   (solde exigible restant)
  #
  #   1. received > 0                → Payment `paid` de `received` (fait historique,
  #                                    quel que soit le statut du SpaceBooking).
  #   2. outstanding > 0 ET price > 0 → Payment `pending` de `outstanding`, SEULEMENT
  #      ET statut vivant                si le SpaceBooking est `confirmed` ou
  #      (confirmed/pending)             `pending` (jamais declined/canceled : pas
  #                                      d'attente sur un séjour mort → skipped).
  #   3. caution                     → rien ; listée en info.
  #
  #   Moyen de paiement : le vocabulaire de `SpaceBooking.payment_method` et de
  #   `Payment.payment_method` est le MÊME (cash, bank_transfer, airbnb,
  #   bookingdotcom — cf. `stays/_form` et `payments/_form`). Le mapping est donc
  #   l'IDENTITÉ, bornée à l'ensemble connu. Valeur vide/inconnue ⇒ on ne crée
  #   rien (Payment exige `payment_method`) et on rapporte `skipped_unknown_method`.
  #
  #   Idempotence : chaque Payment créé porte `space_booking_id`. On saute la
  #   création si un Payment VIVANT du même (space_booking_id, status) existe
  #   déjà. Un re-run après APPLY ne crée donc rien de plus. La rake NE réconcilie
  #   PAS un changement de montant ultérieur — c'est le rôle de la saisie « au fil
  #   de l'eau » (chantier séparé) ; ici on ne fait que l'historique.
  #
  #   Aucun total de séjour n'est modifié ; on appelle `stay.set_payment_status`
  #   après création pour recalculer le STATUT de paiement du séjour.

  # Vocabulaire commun SpaceBooking.payment_method ↔ Payment.payment_method.
  KNOWN_PAYMENT_METHODS = %w[cash bank_transfer airbnb bookingdotcom stripe card].freeze

  desc "Transforme la facturation des SpaceBooking en Payment du séjour (paid + pending). DRY-RUN sauf APPLY=1"
  task billing_to_payments: :environment do
    apply = ENV["APPLY"] == "1"

    report = {
      scanned: [],                # SpaceBooking vivants rattachés à un Stay
      created_paid: [],           # Payment paid créés (détail)
      created_pending: [],        # Payment pending créés (détail)
      skipped_already_paid: [],   # idempotence : paid déjà présent
      skipped_already_pending: [],# idempotence : pending déjà présent
      skipped_unknown_method: [], # argent en jeu mais moyen inconnu/absent
      skipped_dead_status: [],    # solde dû mais SpaceBooking declined/canceled
      skipped_no_billing: [],     # rattaché à un Stay mais aucun signal monétaire
      deposits: [],               # cautions listées (JAMAIS transformées)
      no_stay: 0,                  # SpaceBooking vivants sans Stay (hors périmètre)
      failed: []                  # erreurs inattendues (détail)
    }

    SpaceBooking.find_each do |sb|
      stay = sb.stay
      if stay.nil?
        report[:no_stay] += 1
        next
      end

      report[:scanned] << sb.id

      # Caution : info seule, indépendante de tout le reste. Jamais un paiement.
      if sb.deposit_amount_cents.to_i.positive?
        report[:deposits] << "SpaceBooking ##{sb.id} : caution #{euros(sb.deposit_amount_cents)} (non transformée)"
      end

      price     = sb.price_cents.to_i
      received  = received_cents(sb)
      outstanding = price - received
      method    = KNOWN_PAYMENT_METHODS.include?(sb.payment_method) ? sb.payment_method : nil

      # Aucun signal monétaire (rien reçu, aucun prix dû) → hors périmètre paiements.
      if received <= 0 && price <= 0
        report[:skipped_no_billing] << sb.id
        next
      end

      # Moyen de paiement indispensable pour créer un Payment (validation modèle).
      if method.nil?
        report[:skipped_unknown_method] <<
          "SpaceBooking ##{sb.id} : moyen=#{sb.payment_method.inspect} (reçu #{euros(received)}, dû #{euros(outstanding)})"
        next
      end

      want_paid    = received.positive?
      want_pending = outstanding.positive? && price.positive?

      # Le pending n'a de sens que sur un séjour VIVANT (pas declined/canceled).
      dead = sb.status == "declined" || sb.status == "canceled"
      if want_pending && dead
        report[:skipped_dead_status] << sb.id
        want_pending = false
      end

      # Idempotence : ne pas recréer ce qui existe déjà (Payment vivant, même
      # provenance + statut). Lecture de l'état committé, hors transaction.
      if want_paid && Payment.exists?(space_booking_id: sb.id, status: "paid")
        report[:skipped_already_paid] << sb.id
        want_paid = false
      end
      if want_pending && Payment.exists?(space_booking_id: sb.id, status: "pending")
        report[:skipped_already_pending] << sb.id
        want_pending = false
      end

      next unless want_paid || want_pending

      begin
        # Savepoint PAR SpaceBooking : DRY-RUN = exécuter puis rollback (valide la
        # création sans rien persister) ; APPLY = commit. `requires_new: true`
        # garantit un rollback réel même sous fixtures transactionnelles.
        ActiveRecord::Base.transaction(requires_new: true) do
          if want_paid
            Payment.create!(stay: stay, space_booking: sb, amount_cents: received,
                            payment_method: method, status: "paid")
          end
          if want_pending
            Payment.create!(stay: stay, space_booking: sb, amount_cents: outstanding,
                            payment_method: method, status: "pending")
          end

          # Recalcule le STATUT de paiement du séjour (n'altère aucun total).
          stay.set_payment_status

          raise ActiveRecord::Rollback unless apply
        end

        report[:created_paid]    << "SpaceBooking ##{sb.id} → #{euros(received)} (#{method})" if want_paid
        report[:created_pending] << "SpaceBooking ##{sb.id} → #{euros(outstanding)} (#{method})" if want_pending
      rescue => e
        report[:failed] << "SpaceBooking ##{sb.id} : #{e.class} #{e.message}"
      end
    end

    print_space_billing_report(report, apply)
    abort("ÉCHEC : #{report[:failed].size} SpaceBooking en erreur.") if report[:failed].any?
  end
end

# Montant REÇU d'un SpaceBooking (voir en-tête pour la sémantique). Un séjour
# marqué `paid` sans `paid_amount_cents` renseigné a bien reçu la TOTALITÉ (prix).
def received_cents(sb)
  if sb.payment_status == "paid"
    price = sb.price_cents.to_i
    price.positive? ? price : sb.paid_amount_cents.to_i
  else
    sb.paid_amount_cents.to_i
  end
end

def euros(cents)
  format("%.2f €", cents.to_i / 100.0)
end

def print_space_billing_report(report, apply)
  puts "=== space_bookings:billing_to_payments #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
  puts "SpaceBooking scannés (avec séjour) : #{report[:scanned].size} #{space_billing_ids(report[:scanned])}"
  puts "SpaceBooking sans séjour (hors périm.) : #{report[:no_stay]}"
  puts "Payment PAID créés                : #{report[:created_paid].size}"
  report[:created_paid].each { |l| puts "  + #{l}" }
  puts "Payment PENDING créés             : #{report[:created_pending].size}"
  report[:created_pending].each { |l| puts "  + #{l}" }
  puts "Ignorés — paid déjà présent (idemp.) : #{report[:skipped_already_paid].size} #{space_billing_ids(report[:skipped_already_paid])}"
  puts "Ignorés — pending déjà présent (idemp.) : #{report[:skipped_already_pending].size} #{space_billing_ids(report[:skipped_already_pending])}"
  puts "Ignorés — moyen inconnu/absent    : #{report[:skipped_unknown_method].size}"
  report[:skipped_unknown_method].each { |l| puts "  - #{l}" }
  puts "Ignorés — solde dû mais séjour mort : #{report[:skipped_dead_status].size} #{space_billing_ids(report[:skipped_dead_status])}"
  puts "Ignorés — aucun signal monétaire  : #{report[:skipped_no_billing].size} #{space_billing_ids(report[:skipped_no_billing])}"
  puts "Cautions listées (NON transformées) : #{report[:deposits].size}"
  report[:deposits].each { |l| puts "  · #{l}" }
  unless report[:failed].empty?
    puts "Échecs                            : #{report[:failed].size}"
    report[:failed].each { |l| puts "  ! #{l}" }
  end
  puts(apply ? "OK — paiements créés." : "DRY-RUN — aucune écriture. Relancer avec APPLY=1 pour appliquer.")
end

def space_billing_ids(list)
  list.empty? ? "" : "→ #{list.sort.join(', ')}"
end
