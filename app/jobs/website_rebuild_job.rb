require "net/http"

# Demande au site statique les4sources.be de se reconstruire après une
# publication. Le site lit l'API publique au build : sans ce signal, une fiche
# publiée dans Claudy n'apparaît qu'au prochain build planifié.
#
# Regroupement : la première sauvegarde ouvre une demande (`WebsiteRebuild`,
# en base) et enfile le job pour dans deux minutes ; les suivantes la
# rejoignent. Le job prend la demande en attente et appelle le webhook : un
# `POST` sur `WEBSITE_REBUILD_WEBHOOK_URL` (webhook de déploiement Hatchbox,
# ou `repository_dispatch` GitHub — le corps JSON convient aux deux), avec
# `Authorization: Bearer WEBSITE_REBUILD_WEBHOOK_TOKEN` si le jeton est fourni.
#
# Rattrapage : l'adaptateur de jobs de Claudy vit en mémoire, un redémarrage
# (déploiement) perd le job différé. La demande, elle, reste en base : elle
# repart au démarrage suivant (`recover!`, initialiseur) et dès qu'une
# nouvelle sauvegarde la trouve trop vieille. L'historique se lit par l'API
# agent (`GET /api/v1/website_rebuilds`).
#
# Sans URL, le job marque la demande `skipped` ; hors production il ne fait
# rien non plus, sauf `WEBSITE_REBUILD_ALLOW_NON_PRODUCTION=1`.
class WebsiteRebuildJob < ApplicationJob
  queue_as :default

  WINDOW = 2.minutes
  # Une demande encore en attente au-delà : son job a été perdu.
  STALE_AFTER = WINDOW + 3.minutes

  class << self
    # Ouvre ou rejoint la demande en attente. Renvoie true quand un job a été
    # enfilé. `immediate` saute la fenêtre (demande explicite par l'API).
    def request!(trigger: "publication", immediate: false)
      rebuild, created = WebsiteRebuild.request!(trigger: trigger)
      if created
        immediate ? perform_later : enqueue_after_window
        true
      elsif rebuild.requested_at < STALE_AFTER.ago
        perform_later
        true
      else
        false
      end
    end

    # Au démarrage : une demande restée en attente a perdu son job avec le
    # processus précédent. Elle repart, après ce qui restait de sa fenêtre.
    def recover!
      waiting = WebsiteRebuild.pending.order(:requested_at).first
      return false unless waiting

      remaining = (waiting.requested_at + WINDOW) - Time.current
      remaining.positive? && delayed_enqueue_supported? ? set(wait: remaining).perform_later : perform_later
      true
    end

    def enqueue_after_window
      if delayed_enqueue_supported?
        set(wait: WINDOW).perform_later
      else
        # L'adaptateur :inline (specs) ne sait pas différer : exécuter tout de
        # suite plutôt que de faire planter la sauvegarde qui nous appelle.
        perform_later
      end
    end

    def delayed_enqueue_supported?
      !ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
    end

    def webhook_url
      ENV["WEBSITE_REBUILD_WEBHOOK_URL"].presence
    end

    def webhook_configured?
      webhook_url.present?
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
    rebuild = claim
    return :nothing_pending unless rebuild

    unless self.class.webhook_url
      return skip(rebuild, "WEBSITE_REBUILD_WEBHOOK_URL absente : aucune reconstruction demandée")
    end
    unless self.class.allowed_environment?
      return skip(rebuild, "environnement #{Rails.env} : webhook ignoré (WEBSITE_REBUILD_ALLOW_NON_PRODUCTION=1 pour forcer)")
    end

    response = self.class.post(self.class.webhook_url)
    ok = response.code.to_i.between?(200, 299)
    rebuild.update!(status: ok ? "sent" : "failed", response_code: response.code)
    Rails.logger.info("[WebsiteRebuildJob] demande ##{rebuild.id} (#{rebuild.requests_count} sauvegarde(s)) → #{response.code}")
    response.code
  rescue StandardError => e
    rebuild&.update_columns(status: "failed", error_message: e.message.to_s.truncate(250), updated_at: Time.current)
    Rails.logger.error("[WebsiteRebuildJob] demande ##{rebuild&.id} : #{e.class} #{e.message}")
    :failed
  end

  private

  # Prend la demande en attente, une seule fois même si deux jobs se croisent.
  def claim
    WebsiteRebuild.transaction do
      rebuild = WebsiteRebuild.pending.order(:requested_at).lock("FOR UPDATE SKIP LOCKED").first
      rebuild&.update!(status: "dispatching", dispatched_at: Time.current)
      rebuild
    end
  end

  def skip(rebuild, message)
    rebuild.update!(status: "skipped", error_message: message)
    Rails.logger.info("[WebsiteRebuildJob] #{message}")
    :skipped
  end
end
