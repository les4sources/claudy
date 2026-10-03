# Reçoit les pages vues et événements du site www.les4sources.be
# (statistiques sans cookie, 2026-10-03). Hors de `/api/public`, qui reste en
# lecture seule.
#
# Le site envoie par `navigator.sendBeacon` un JSON en `text/plain` — type
# « simple » : pas de requête préalable CORS, et la réponse n'est pas lue.
# Clés courtes pour un envoi léger : k (pageview|event), n (nom de
# l'événement), u (URL de la page), r (référent), t (destination).
#
# Seule l'origine du site est acceptée (`SITE_STATS_ORIGINS`, par défaut
# https://www.les4sources.be), et seuls les événements du SITE : les
# étapes du funnel ne s'écrivent que côté serveur. La réponse ne pose
# jamais de cookie, même quand la session d'un membre est lue pour
# l'écarter du décompte.
class SiteHitsController < ActionController::Base
  skip_forgery_protection

  DEFAULT_ORIGINS = "https://www.les4sources.be".freeze
  MAX_BODY_BYTES = 4.kilobytes

  # Limite de débit en mémoire du processus, clé hachée : le magasin par
  # défaut (fichiers dans tmp/cache) laisserait l'IP de chaque visiteur
  # sur le disque, sans expiration.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)

  rate_limit to: 120, within: 1.minute, store: RATE_LIMIT_STORE,
             by: -> { Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}|#{SiteStats::Tracker.client_ip(request)}") }

  before_action { request.session_options[:skip] = true }

  def create
    return head(:content_too_large) if request.content_length.to_i > MAX_BODY_BYTES
    return head(:content_too_large) if request.raw_post.bytesize > MAX_BODY_BYTES

    payload = parse_payload
    return head(:bad_request) if payload.nil?
    return head(:forbidden) unless allowed_origin?(payload["u"])
    return head(:no_content) unless acceptable?(payload)

    SiteStats::Tracker.new(request).record(
      kind: payload["k"], name: (payload["n"] if payload["k"] == "event"), url: payload["u"],
      referrer: payload["r"], target: payload["t"]
    )
    head :no_content
  end

  private

  def acceptable?(payload)
    case payload["k"]
    when "pageview" then true
    when "event" then SiteHit::SITE_EVENTS.include?(payload["n"])
    else false
    end
  end

  def allowed_origin?(page_url)
    allowed = ENV.fetch("SITE_STATS_ORIGINS", DEFAULT_ORIGINS).split(",").map(&:strip)
    origin = request.headers["Origin"].presence
    uri = URI.parse(page_url.to_s)
    page_origin = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless [80, 443, nil].include?(uri.port)}"

    allowed.include?(page_origin) && (origin.nil? || allowed.include?(origin))
  rescue URI::InvalidURIError
    false
  end

  # Un objet JSON dont chaque valeur est une chaîne courte, sans octet nul
  # (que PostgreSQL refuse) — sinon nil.
  def parse_payload
    data = JSON.parse(request.raw_post)
    return nil unless data.is_a?(Hash)
    return nil unless data.values.all? { |value| value.nil? || (value.is_a?(String) && value.length <= 2_000 && !value.include?("\u0000")) }

    data
  rescue JSON::ParserError
    nil
  end
end
