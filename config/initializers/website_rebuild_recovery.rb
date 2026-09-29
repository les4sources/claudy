# Rattrapage des reconstructions du site perdues au redémarrage (voir
# `WebsiteRebuildJob.recover!`). Seulement dans le serveur web : ni console,
# ni rake (migrations comprises), ni specs.
Rails.application.config.after_initialize do
  next unless Rails.env.production? && File.basename($PROGRAM_NAME).start_with?("puma")

  WebsiteRebuildJob.recover!
rescue ActiveRecord::ActiveRecordError => e
  Rails.logger.warn("[WebsiteRebuildJob] rattrapage au démarrage impossible : #{e.message}")
end
