Sentry.init do |config|
  if Rails.env.production? && ENV.fetch('SENTRY_DSN')
    config.dsn = ENV.fetch('SENTRY_DSN')
  end
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Set traces_sample_rate to 1.0 to capture 100%
  # of transactions for performance monitoring.
  # We recommend adjusting this value in production.
  # config.traces_sample_rate = 1.0
  # or
  config.traces_sampler = lambda do |context|
    false
  end
end
