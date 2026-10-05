# Les tâches planifiées (cron Hatchbox, cf. README « Tâches planifiées »)
# envoient leurs emails par `deliver_later`. En production, l'adaptateur Active
# Job est `:async` : le job tourne dans un fil du processus qui l'a mis en file.
# Or un `rake` s'arrête dès sa dernière ligne, et Ruby tue alors les fils
# encore en cours : les emails pas encore partis sont perdus, alors que la
# tâche les a déjà horodatés comme envoyés (`balance_reminder_sent_at`…) et ne
# les renverra jamais.
#
# On laisse donc la file se vider avant de sortir. Le serveur web n'est pas
# concerné : il vit assez longtemps pour livrer ses jobs.
Rails.application.config.after_initialize do
  next if File.basename($PROGRAM_NAME).start_with?("puma")

  at_exit do
    adapter = ActiveJob::Base.queue_adapter
    next unless adapter.is_a?(ActiveJob::QueueAdapters::AsyncAdapter)

    # Plafonné : un envoi qui ne répond plus ne doit pas bloquer le cron.
    Thread.new { adapter.shutdown(wait: true) }.join(120)
  end
end
