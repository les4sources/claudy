module Api
  module Public
    module V1
      # API PUBLIQUE, sans authentification, en lecture seule : ce que le site
      # les4sources.be lit au build (événements, activités, catégories). Rien
      # de personnel n'en sort — pas d'e-mail, de téléphone ni de participant.
      # Distincte de `Api::V1` (agents internes, bearer). Réponses cacheables
      # cinq minutes avec ETag : le site et les CDN peuvent revalider à bas coût.
      class BaseController < ActionController::Base
        include ActiveStorage::SetCurrent

        skip_forgery_protection
        layout false

        CACHE_TTL = 5.minutes

        helper_method :absolute_url, :public_html

        private

        # Pose les en-têtes de cache et répond 304 si l'ETag du client est à jour
        # (dans ce cas l'action ne rend rien : `performed?` est vrai).
        def serve_cached(etag_parts)
          expires_in CACHE_TTL, public: true
          fresh_when(etag: etag_parts, public: true)
        end

        def absolute_url(path)
          return path if path.blank? || path.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

          "#{request.base_url}#{path}"
        end

        # Rendu ActionText assaini, sans script, avec des URLs absolues sur les
        # images et liens internes (le site les télécharge au build).
        def public_html(rich_text)
          return nil if rich_text.blank?

          fragment = Nokogiri::HTML::DocumentFragment.parse(rich_text.to_s)
          fragment.css("script").remove
          fragment.css("[src], [href]").each do |node|
            %w[src href].each do |attribute|
              value = node[attribute]
              node[attribute] = absolute_url(value) if value&.start_with?("/")
            end
          end
          fragment.to_html
        end

        def parse_date(value)
          return nil if value.blank?

          Date.iso8601(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
