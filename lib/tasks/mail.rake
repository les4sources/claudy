namespace :mail do
  # Messagerie, phase 1. À lancer par le cron Hatchbox (toutes les 15 minutes
  # suffisent : une facture n'est pas une urgence à la minute).
  desc "Relève les boîtes mail actives (lecture seule) puis prépare les propositions de tri."
  task sync: :environment do
    MailIntake::Run.new.run!.each { |line| puts "[mail:sync] #{line}" }
  end

  # Déclare une boîte à lire. Le mot de passe, lui, va dans l'ENV
  # (`MAIL_PASSWORD_<PARTIE LOCALE>`), jamais en base.
  desc "Déclare une boîte : bin/rails mail:add_account ADDRESS=compta@les4sources.be PURPOSE=accounting"
  task add_account: :environment do
    address = ENV.fetch("ADDRESS")
    account = MailAccount.find_or_create_by!(address: address) { |a| a.purpose = ENV.fetch("PURPOSE", "accounting") }
    puts "[mail:add_account] #{account.address} (##{account.id}) — mot de passe attendu dans #{account.password_env_key}"
  end
end
