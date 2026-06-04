namespace :activity_carriers do
  desc "Crée un compte d'accès (User) pour chaque porteur d'activité (Human avec email, sans compte). Passer SEND_INVITES=1 pour envoyer les emails d'invitation."
  task ensure_accounts: :environment do
    send_invitation = ENV["SEND_INVITES"] == "1"

    carriers = Human.with_email
                    .where(id: Experience.where.not(human_id: nil).select(:human_id))
                    .order(:name)

    puts "#{carriers.count} porteur·euse(s) avec email."
    puts "Envoi des invitations : #{send_invitation ? 'OUI' : 'non (SEND_INVITES=1 pour activer)'}"

    created = 0
    skipped = 0

    carriers.find_each do |human|
      if human.user.present?
        skipped += 1
        next
      end

      service = Humans::CreateAccountService.new(human: human, send_invitation: send_invitation)
      if service.run
        created += 1
        puts "  ✓ Compte créé pour #{human.name} (#{human.email})"
      else
        puts "  ✗ #{human.name} : #{service.error_message}"
      end
    end

    puts "Terminé : #{created} compte(s) créé(s), #{skipped} déjà existant(s)."
  end
end
