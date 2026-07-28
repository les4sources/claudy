namespace :sent_emails do
  desc "Rapatrie l'historique des emails Postmark dans le journal client (idempotent). Options : DAYS, LIMIT, THROTTLE, DRY_RUN"
  task backfill: :environment do
    # Postmark ne garde le contenu des messages qu'environ 45 jours : passé ce
    # délai la recherche renvoie encore le sujet et la date, mais plus le corps.
    # DAYS borne donc la fenêtre utile ; LIMIT borne le nombre de messages
    # parcourus (chaque message importé coûte un appel API de détail).
    days     = (ENV["DAYS"] || 45).to_i
    limit    = (ENV["LIMIT"] || 2000).to_i
    throttle = (ENV["THROTTLE"] || 0.1).to_f
    dry_run  = ENV["DRY_RUN"].present?

    puts "Backfill Postmark → journal des emails clients"
    puts "  fenêtre : #{days} jours · plafond : #{limit} messages · pause : #{throttle}s#{' · DRY RUN' if dry_run}"

    stats = SentEmails::PostmarkBackfill.new(
      days: days, limit: limit, throttle: throttle, dry_run: dry_run
    ).run

    puts "  #{stats[:scanned]} message(s) parcouru(s)"
    puts "  ↳ #{stats[:imported]} importé(s)"
    puts "  ↳ #{stats[:skipped]} déjà journalisé(s)"
    puts "  ↳ #{stats[:unmatched]} sans client correspondant (équipe, porteurs, bcc)"
    puts "  ↳ #{stats[:without_body]} importé(s) sans corps (contenu expiré chez Postmark)" if stats[:without_body].positive?
  end
end
