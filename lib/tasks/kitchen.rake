namespace :kitchen do
  desc "Envoie à chaque responsable le programme cuisine des 14 prochains jours (vendredi, idempotent par semaine ISO ; FORCE=1 pour forcer)"
  task weekly_digest: :environment do
    result = Kitchen::WeeklyDigest.new(force: ENV["FORCE"].present?).run
    puts "[kitchen:weekly_digest] #{result}"
  end

  desc "Rappelle de commander le pain 5 jours avant chaque prestation acceptée (quotidien, idempotent)"
  task bread_reminders: :environment do
    result = Kitchen::BreadReminders.new.run
    puts "[kitchen:bread_reminders] #{result}"
  end
end
