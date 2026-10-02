require "net/http"

module Jev
  # Client de Jev, le modèle « System One » de TypeSafe (messagerie, phase 1).
  #
  # Jev ne génère pas de texte : il rend des jugements typés — un choix parmi
  # des options qu'on lui donne, une probabilité de oui, un score. C'est pour
  # ça qu'il trie les mails : quand il choisit un montant, c'est un des montants
  # que le code a trouvés dans le PDF, il ne peut pas en inventer un.
  #
  # Sans `TYPESAFE_API_KEY`, `configured?` est faux et les appelants se passent
  # de proposition plutôt que d'échouer.
  class Client
    ENDPOINT = URI("https://api.typesafe.ai/v1/systemone")
    MODEL = "jev-latest".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    class Error < StandardError; end
    class NotConfigured < Error; end

    def self.api_key = ENV["TYPESAFE_API_KEY"].presence

    def initialize(api_key: self.class.api_key)
      @api_key = api_key
    end

    def configured? = @api_key.present?

    # `questions` : { id => { type:, instructions:, criteria: } }, cf. l'API
    # TypeSafe. Renvoie { id => réponse brute } (`choice`, `confidence`,
    # `probabilities` pour un choix ; `noul` pour un oui/non).
    def ask(state:, questions:)
      raise NotConfigured, "TYPESAFE_API_KEY absente" unless configured?
      return {} if questions.empty?

      response = post(state: state, model: MODEL, questions: questions)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Jev a répondu #{response.code} : #{response.body.to_s.truncate(200)}"
      end

      JSON.parse(response.body).fetch("answers")
    rescue JSON::ParserError, KeyError => e
      raise Error, "réponse de Jev illisible (#{e.class})"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error, "Jev injoignable (#{e.class})"
    end

    private

    def post(payload)
      http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
      http.request(request)
    end
  end
end
