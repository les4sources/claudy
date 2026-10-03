module Api
  module Public
    module V1
      # Reçoit les pages vues et événements du site www.les4sources.be
      # (statistiques sans cookie, 2026-10-03).
      #
      # Le site envoie par `navigator.sendBeacon` un JSON en `text/plain` — type
      # « simple » : pas de requête préalable CORS, et la réponse n'est pas lue.
      # Clés courtes pour un envoi léger : k (pageview|event), n (nom de
      # l'événement), u (URL de la page), r (référent), t (destination).
      #
      # Seule l'origine du site est acceptée (`SITE_STATS_ORIGINS`, par défaut
      # https://www.les4sources.be). La réponse ne pose jamais de cookie, même
      # quand la session d'un membre est lue pour l'écarter du décompte.
      class HitsController < ActionController::Base
        skip_forgery_protection

        DEFAULT_ORIGINS = "https://www.les4sources.be".freeze
        MAX_BODY_BYTES = 4.kilobytes

        rate_limit to: 120, within: 1.minute,
                   by: -> { request.headers["CF-Connecting-IP"].presence || request.remote_ip }

        before_action { request.session_options[:skip] = true }

        def create
          return head(:forbidden) unless allowed_origin?
          return head(:payload_too_large) if request.raw_post.bytesize > MAX_BODY_BYTES

          payload = parse_payload
          return head(:bad_request) if payload.nil?

          SiteStats::Tracker.new(request).record(
            kind: payload["k"], name: payload["n"], url: payload["u"],
            referrer: payload["r"], target: payload["t"]
          )
          head :no_content
        end

        private

        def allowed_origin?
          allowed = ENV.fetch("SITE_STATS_ORIGINS", DEFAULT_ORIGINS).split(",").map(&:strip)
          origin = request.headers["Origin"].presence
          page_origin = begin
            uri = URI.parse(parse_payload&.dig("u").to_s)
            "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless [80, 443, nil].include?(uri.port)}"
          rescue URI::InvalidURIError
            nil
          end

          allowed.include?(page_origin) && (origin.nil? || allowed.include?(origin))
        end

        def parse_payload
          @payload ||= begin
            data = JSON.parse(request.raw_post)
            data.is_a?(Hash) && data.values.all? { |value| value.nil? || value.is_a?(String) } ? data : nil
          rescue JSON::ParserError
            nil
          end
        end
      end
    end
  end
end
