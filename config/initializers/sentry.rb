Sentry.init do |config|
  if Rails.env.production? && ENV.fetch('SENTRY_DSN')
    config.dsn = ENV.fetch('SENTRY_DSN')
  end

  # Sans DSN explicite, sentry-ruby retombe sur la variable d'environnement
  # SENTRY_DSN — présente dans le .env local. Ce garde-fou empêche dev et test
  # d'envoyer quoi que ce soit, peu importe ce que l'environnement contient.
  config.enabled_environments = %w[production]

  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Performance monitoring — activé pour localiser les routes lentes
  # (N+1 suspecté dans le calendrier, pages#calendar). App interne à faible
  # trafic → 100 % d'échantillonnage en prod pour des données complètes.
  # Repasser à un taux plus bas (ex. 0.2) une fois le diagnostic terminé.
  config.traces_sample_rate = Rails.env.production? ? 1.0 : 0.0
end
