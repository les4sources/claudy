require "net/http"

# Demande au site statique les4sources.be de se reconstruire après une
# publication. Le site lit l'API publique au build : sans ce signal, une fiche
# publiée dans Claudy n'apparaît qu'au prochain build manuel.
#
# Regroupement : plusieurs sauvegardes dans une fenêtre de deux minutes ne
# déclenchent qu'UN appel (un verrou en cache pose la fenêtre, le job attend
# sa fin). L'appel est un `POST` sur `WEBSITE_REBUILD_WEBHOOK_URL` (webhook de
# déploiement Coolify, ou `repository_dispatch` GitHub — le corps JSON convient
# aux deux), avec `Authorization: Bearer WEBSITE_REBUILD_WEBHOOK_TOKEN` si le
# jeton est fourni. Sans URL, le job journalise et ne fait rien ; hors
# production il ne fait rien non plus, sauf `WEBSITE_REBUILD_ALLOW_NON_PRODUCTION=1`.
class WebsiteRebuildJob < ApplicationJob
  queue_as :default

  WINDOW = 2.minutes
  LOCK_KEY = "website_rebuild:scheduled".freeze

  class << self
    # Enfile une reconstruction si aucune n'est déjà prévue dans la fenêtre.
    # Renvoie true quand un job a été enfilé.
    def request!
      return false unless Rails.cache.write(LOCK_KEY, Time.current.to_i, unless_exist: true, expires_in: WINDOW)

      if delayed_enqueue_supported?
        set(wait: WINDOW).perform_later
      else
        # L'adaptateur :inline (specs) ne sait pas différer : exécuter tout de
        # suite plutôt que de faire planter la sauvegarde qui nous appelle.
        perform_later
      end
      true
    end

    def delayed_enqueue_supported?
      !ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
    end

    def webhook_url
      ENV["WEBSITE_REBUILD_WEBHOOK_URL"].presence
    end

    def allowed_environment?
      Rails.env.production? || ENV["WEBSITE_REBUILD_ALLOW_NON_PRODUCTION"] == "1"
    end

    # Isolé pour être remplacé dans les specs.
    def post(url)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      token = ENV["WEBSITE_REBUILD_WEBHOOK_TOKEN"].presence
      request["Authorization"] = "Bearer #{token}" if token
      request.body = { event_type: "website-rebuild", client_payload: { source: "claudy" } }.to_json

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end
    end
  end

  def perform
    Rails.cache.delete(LOCK_KEY)

    url = self.class.webhook_url
    unless url
      Rails.logger.info("[WebsiteRebuildJob] WEBSITE_REBUILD_WEBHOOK_URL absente : aucune reconstruction demandée")
      return :skipped
    end
    unless self.class.allowed_environment?
      Rails.logger.info("[WebsiteRebuildJob] environnement #{Rails.env} : webhook ignoré (WEBSITE_REBUILD_ALLOW_NON_PRODUCTION=1 pour forcer)")
      return :skipped
    end

    response = self.class.post(url)
    Rails.logger.info("[WebsiteRebuildJob] POST #{url} → #{response.code}")
    response.code
  end
end
