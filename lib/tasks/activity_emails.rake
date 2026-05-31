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
end
