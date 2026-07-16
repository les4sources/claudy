namespace :activity_emails do
  desc "Envoie les emails d'invitation activités aux séjours arrivant dans ~30 jours (sans email déjà envoyé)"
  task send: :environment do
    window_start = Date.today + 28
    window_end   = Date.today + 35

    stays = Stay.where(activity_email_sent_at: nil)
                .where(arrival_date: window_start..window_end)
                .where.not(status: %w[cancelled])
                .includes(:customer)

    puts "#{stays.count} séjour(s) éligible(s)."

    stays.each do |stay|
      next if stay.activity_selection_token.blank?
      next if stay.customer.email.blank? || stay.customer.email == Customer::CATCH_ALL_EMAIL

      # N'envoyer que si des disponibilités existent pour ces dates
      has_slots = ExperienceAvailability.for_date_range(stay.arrival_date, stay.departure_date)
                                        .joins(:experience)
                                        .where(experiences: { deleted_at: nil })
                                        .exists?
      unless has_slots
        puts "  ↳ #{stay.id} : pas de disponibilités sur #{stay.arrival_date} → skip"
        next
      end

      ActivitySelectionMailer.invitation(stay).deliver_later
      stay.update_column(:activity_email_sent_at, Time.current)
      puts "  ↳ #{stay.id} (#{stay.customer.email}) : email envoyé ✓"
    end
  end

  desc "Relance le solde exigible ~14 jours avant l'arrivée (sans blocage, idempotent)"
  task balance_reminder: :environment do
    # Fenêtre J-14 avec une marge de rattrapage : un cron qui saute un jour
    # récupère quand même le séjour. L'idempotence (colonne
    # `balance_reminder_sent_at`) empêche tout second envoi, la fenêtre large
    # est donc sans risque de doublon.
    window_start = Date.today + 12
    window_end   = Date.today + 14

    stays = Stay.where(balance_reminder_sent_at: nil)
                .where(arrival_date: window_start..window_end)
                .where.not(status: %w[cancelled])
                .includes(:customer)

    # `balance_due_cents` est CALCULÉ en Ruby (barème activités) : on filtre en
    # mémoire, jamais en SQL. Ne relance QUE les séjours dont l'EXIGIBLE reste
    # impayé (activités `pending` non facturables déjà exclues, cf. Phase 3).
    eligible = stays.select(&:payable_now?)

    puts "#{eligible.size} séjour(s) avec solde exigible sur #{stays.count} dans la fenêtre J-14."

    eligible.each do |stay|
      if stay.customer.email.blank? || stay.customer.email == Customer::CATCH_ALL_EMAIL
        # Pas d'horodatage : rien n'a été envoyé, on reste éligible au prochain
        # passage (au cas où l'email du client serait corrigé entre-temps).
        puts "  ↳ #{stay.id} : email client absent/catch-all → skip"
        next
      end

      # AUCUN blocage : on relance vers la page de paiement existante, sans
      # toucher aux réservations (aucune annulation).
      StayBalanceReminderMailer.reminder(stay).deliver_later
      stay.update_column(:balance_reminder_sent_at, Time.current)
      puts "  ↳ #{stay.id} (#{stay.customer.email}) : relance solde envoyée ✓ (reste #{stay.balance_due_cents} c.)"
    end
  end
end
