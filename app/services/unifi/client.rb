require "net/http"

module Unifi
  # Lecture seule de l'API cloud UniFi Site Manager (epic #348, phase 10) : le
  # statut en direct des équipements réseau du domaine, pour les pastilles de
  # la couche Ethernet. On n'écrit JAMAIS là-bas.
  #
  # Même contrat que `TranchesDeVie::Client` : sans `UNIFI_API_KEY`, le client
  # est `configured? == false` et ne part pas. Mais là où Tranches de Vie lève
  # des erreurs typées (une action de l'utilisateur échoue, il doit le savoir),
  # un statut est un décor : une panne de l'API rend une liste vide et
  # `available? == false`, un avertissement au journal, et jamais d'exception
  # jusqu'à l'UI — la carte doit s'afficher même quand UniFi ne répond pas.
  #
  # La réponse est gardée 60 s dans `Rails.cache` : la carte rafraîchit ses
  # pastilles toutes les minutes et chaque fiche relit la liste. Une panne
  # n'est pas mise en cache, l'appel suivant réessaie.
  class Client
    BASE_URL = "https://api.ui.com".freeze
    # `/v1/devices` en version stable ; l'API a longtemps servi `/ea/devices`
    # (early access). Une constante pour basculer sans chercher.
    DEVICES_PATH = "/v1/devices".freeze
    CACHE_KEY = "unifi/devices/v1".freeze
    CACHE_TTL = 60.seconds
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5

    class Error < StandardError; end

    def self.api_key
      ENV["UNIFI_API_KEY"].presence
    end

    def self.configured?
      api_key.present?
    end

    def initialize(api_key: self.class.api_key)
      @api_key = api_key
    end

    def configured?
      @api_key.present?
    end

    # Vrai quand la dernière lecture a abouti. Sans clé ou en panne : faux.
    def available?
      devices
      @available
    end

    # Tous les équipements de tous les hôtes du compte, normalisés.
    def devices
      @devices ||= load_devices
    end

    def device(id)
      return nil if id.blank?

      devices.find { |d| d.id == id.to_s }
    end

    private

    def load_devices
      @available = false
      return [] unless configured?

      rows = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_rows }
      @available = true
      rows.map { |row| Device.new(**row.symbolize_keys) }
    rescue Error => e
      Rails.logger.warn("[UniFi] statut indisponible : #{e.message}")
      []
    end

    # Des hashes simples (pas de Struct) pour que le cache reste sérialisable
    # quel que soit le store.
    def fetch_rows
      Array(get(DEVICES_PATH)["data"]).flat_map do |host|
        last_seen_at = parse_time(host["updatedAt"])
        Array(host["devices"]).map { |raw| normalize(raw, host["hostName"], last_seen_at) }
      end
    end

    def normalize(raw, host_name, last_seen_at)
      model = raw["model"].presence || raw["shortname"].presence
      {
        id: (raw["id"].presence || raw["mac"]).to_s,
        mac: raw["mac"].presence,
        name: raw["name"].presence || model || raw["mac"],
        model: model,
        ip: raw["ip"].presence,
        status: raw["status"].presence&.downcase,
        last_seen_at: parse_time(raw["updatedAt"]) || last_seen_at,
        host_name: host_name.presence
      }
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end

    def get(path)
      uri = URI.parse("#{BASE_URL}#{path}")
      request = Net::HTTP::Get.new(uri)
      request["X-API-KEY"] = @api_key
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      raise Error, "l'API a répondu #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body.to_s.presence || "{}")
    rescue JSON::ParserError
      raise Error, "réponse illisible"
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise Error, "pas de réponse à temps"
    rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise Error, "API injoignable (#{e.class})"
    end
  end
end
