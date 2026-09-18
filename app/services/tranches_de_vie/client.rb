require "net/http"

module TranchesDeVie
  # Lecture seule de l'API de Tranches de Vie (contrat : les4sources/tranchesdevie2#290).
  # On n'écrit JAMAIS là-bas — une party se gère chez elle, ici on la reflète.
  #
  # Sans `TRANCHESDEVIE_API_KEY`, le client est `configured? == false` et refuse
  # de partir : l'UI le sait et désactive le bouton plutôt que d'échouer en vol.
  # Même forme d'appel sortant que `WebsiteRebuildJob` — Net::HTTP, timeouts
  # explicites, aucune dépendance en plus.
  class Client
    DEFAULT_BASE_URL = "https://tranchesdevie.les4sources.be".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_PER_PAGE = 100
    # Garde-fou de pagination : une boucle qui suit `_links.next` sans borne est
    # une boucle infinie qui attend son bug côté serveur.
    MAX_PAGES = 20

    # Erreur typée : tout ce qui sort d'ici est un `TranchesDeVie::Client::Error`,
    # jamais un `Net::` brut. Les appelants affichent `message` tel quel.
    class Error < StandardError; end
    class NotConfigured < Error; end
    class NotFound < Error; end

    def self.base_url
      ENV["TRANCHESDEVIE_API_URL"].presence || DEFAULT_BASE_URL
    end

    def self.api_key
      ENV["TRANCHESDEVIE_API_KEY"].presence
    end

    def self.configured?
      api_key.present?
    end

    def initialize(base_url: self.class.base_url, api_key: self.class.api_key)
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key
    end

    def configured?
      @api_key.present?
    end

    # Les parties privées PAYÉES tenues entre deux dates. Renvoie la liste des
    # commandes (hashes bruts), pagination suivie.
    def private_parties(held_on_from:, held_on_to:, per_page: MAX_PER_PAGE)
      orders = []
      page = 1

      while page <= MAX_PAGES
        body = get("/api/v1/orders", kind: "private_party", paid: "true",
                                     held_on_from: held_on_from.to_s, held_on_to: held_on_to.to_s,
                                     page: page, per_page: [per_page, MAX_PER_PAGE].min)
        batch = Array(body["data"])
        orders.concat(batch)
        break if batch.empty?
        break unless body.dig("_links", "next").present?
        page += 1
      end

      orders
    end

    # Une commande par son identifiant. `NotFound` sur 404 — l'appelant en fait
    # une annulation, une commande disparue chez eux n'existe plus ici non plus.
    def order(external_id)
      get("/api/v1/orders/#{external_id}")["data"]
    end

    private

    def get(path, **query)
      raise NotConfigured, "Connexion à Tranches de Vie non configurée" unless configured?

      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(query.compact) if query.any?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      handle(response, uri)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise Error, "Tranches de Vie n'a pas répondu à temps."
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
      raise Error, "Tranches de Vie est injoignable (#{e.class})."
    end

    def handle(response, uri)
      case response
      when Net::HTTPSuccess
        parse(response.body)
      when Net::HTTPNotFound
        raise NotFound, "Commande introuvable sur Tranches de Vie (#{uri.path})."
      when Net::HTTPUnauthorized, Net::HTTPForbidden
        raise Error, "Tranches de Vie a refusé la clé d'API."
      else
        raise Error, "Tranches de Vie a répondu #{response.code}."
      end
    end

    def parse(body)
      JSON.parse(body.to_s.presence || "{}")
    rescue JSON::ParserError
      raise Error, "Réponse illisible de Tranches de Vie."
    end
  end
end
