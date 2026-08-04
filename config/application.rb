require_relative "boot"

require "rails"
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require "active_storage/engine"
require 'action_controller/railtie'
require 'action_mailer/railtie'
require "action_mailbox/engine"
require "action_text/engine"
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Claudy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Convention Rails 7.1. No-op aujourd'hui : lib/ ne contient aucun code Ruby
    # autochargeable (assets, tâches rake, gabarits de générateurs). Le jour où du
    # code arrive dans lib/, il sera autochargé sans config supplémentaire.
    config.autoload_lib(ignore: %w(assets tasks templates))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Brussels"
    # config.eager_load_paths << Rails.root.join("extras")

    config.i18n.default_locale = :fr
    # Pages client à jeton trilingues (issue #15). Le fallback vers le FR vaut
    # dans tous les environnements : une clé non encore traduite s'affiche en
    # français au lieu de casser la page.
    config.i18n.available_locales = [:fr, :nl, :en]
    config.i18n.fallbacks = [:fr]

    # ViewComponent 4 : la config des previews vit sous `previews.*`.
    config.view_component.previews.paths << "#{Rails.root}/spec/components/previews"

    config.action_mailer.delivery_method = :postmark
    config.action_mailer.postmark_settings = { api_token: ENV.fetch('POSTMARK_API_TOKEN') }
    # Journal des emails envoyés aux clients (visible sur la fiche client).
    # Déclaré en chaîne : la classe n'est constantisée qu'au chargement
    # d'ActionMailer, pas au boot du framework.
    config.action_mailer.observers = ["SentEmails::Observer"]
  end
end
