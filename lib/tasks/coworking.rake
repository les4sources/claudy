namespace :coworking do
  desc "Rappel J-30 avant expiration d'un pack coworking avec crédits restants (idempotent)"
  task send_expiry_reminders: :environment do
    # Fenêtre : packs expirant dans les 30 prochains jours et dont le rappel n'a
    # pas encore été envoyé. Rejouable sans risque de doublon — la colonne
    # `expiry_reminder_sent_at` verrouille tout second envoi (même pattern que
    # `activity_emails:balance_reminder`). Le filtrage fin (payé, crédits
    # restants, client vivant et joignable) se fait en Ruby car ces états sont
    # calculés, jamais stockés.
    candidates = CoworkingPack.expiry_reminder_candidates.includes(:customer, :payments)
    eligible = candidates.select(&:expiry_reminder_due?)

    puts "#{eligible.size} pack(s) éligible(s) au rappel d'expiration sur #{candidates.size} dans la fenêtre J-30."

    eligible.each do |pack|
      CoworkingMailer.pack_expiring(pack).deliver_later
      pack.update_column(:expiry_reminder_sent_at, Time.current)
      puts "  ↳ pack ##{pack.id} (#{pack.customer.email}) : rappel envoyé ✓ " \
           "(#{pack.days_remaining} j restant, expire le #{pack.expires_at.to_date})"
    end
  end
end
