require "net/http"

module Vies
  # Contrôle d'un numéro de TVA auprès de VIES, le registre européen (API REST
  # publique de la Commission, sans clé).
  #
  # Utilisé par le funnel de réservation quand le client demande une facture.
  # VIES tombe souvent (un État membre en maintenance suffit) : ce client ne
  # lève JAMAIS. Il répond `:valid`, `:invalid` ou `:unavailable`, et c'est à
  # l'appelant de ne pas bloquer une réservation sur `:unavailable`.
  # Même forme d'appel que `PlantNet::Client` : Net::HTTP, timeouts courts.
  class Client
    ENDPOINT = "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/%<country>s/vat/%<number>s".freeze
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    # `name` : la raison sociale que VIES connaît (certains pays ne la donnent
    # pas — elle vaut alors nil).
    Result = Data.define(:status, :name) do
      def valid? = status == :valid
      def invalid? = status == :invalid
      def unavailable? = status == :unavailable
    end

    def self.check(vat) = new.check(vat)

    # `vat` : la forme compacte (« BE0123456789 »).
    def check(vat)
      country, number = vat.to_s[0, 2], vat.to_s[2..].to_s
      response = get(format(ENDPOINT, country: country, number: number))
      return unavailable unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      if body["isValid"] == true
        Result.new(status: :valid, name: clean_name(body["name"]))
      elsif body["userError"].to_s.in?(%w[VALID INVALID])
        Result.new(status: :invalid, name: nil)
      else
        unavailable
      end
    rescue StandardError
      unavailable
    end

    private

    def unavailable = Result.new(status: :unavailable, name: nil)

    # VIES écrit « --- » quand le pays ne publie pas le nom.
    def clean_name(name)
      name = name.to_s.squish
      name.presence unless name.match?(/\A-+\z/)
    end

    def get(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json"))
    end
  end
end
