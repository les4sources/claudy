require "net/http"

module PlantNet
  # Client de Pl@ntNet, l'identification d'une plante par photo (« Placer une
  # plante »). Jev ne lit que du texte : c'est ici, et non chez lui, qu'une
  # photo devient une liste d'espèces probables.
  #
  # On envoie une à cinq photos du MÊME individu (feuille, fleur, fruit, écorce,
  # port) ; Pl@ntNet répond ses meilleures espèces, chacune avec un score. Rien
  # n'est retenu ici : la liste attend le « C'est elle » d'un humain.
  #
  # Sans `PLANTNET_API_KEY`, `configured?` est faux et la fiche désactive le
  # bouton plutôt que d'échouer. Même forme d'appel que `Jev::Client` :
  # Net::HTTP, timeouts explicites, aucune dépendance en plus.
  class Client
    ENDPOINT = URI("https://my-api.plantnet.org/v2/identify/all")
    MAX_IMAGES = 5
    MAX_RESULTS = 5
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    class Error < StandardError; end
    class NotConfigured < Error; end

    # `latin_name` sans auteur (« Malus domestica »), `score` entre 0 et 1.
    Candidate = Data.define(:latin_name, :authorship, :common_names, :genus, :family, :score, :gbif_id)

    def self.api_key = ENV["PLANTNET_API_KEY"].presence

    def self.configured? = api_key.present?

    def initialize(api_key: self.class.api_key)
      @api_key = api_key
    end

    def configured? = @api_key.present?

    # `images` : des { io:, filename:, content_type: }. Renvoie les candidats du
    # plus probable au moins probable ; une liste vide quand Pl@ntNet ne voit
    # aucune plante sur les photos (il répond alors 404).
    def identify(images)
      raise NotConfigured, "PLANTNET_API_KEY absente" unless configured?
      raise Error, "Aucune photo à identifier" if images.empty?
      raise Error, "#{MAX_IMAGES} photos au plus" if images.size > MAX_IMAGES

      response = post(images)
      return [] if response.is_a?(Net::HTTPNotFound)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Pl@ntNet a répondu #{response.code} : #{response.body.to_s.truncate(200)}"
      end

      JSON.parse(response.body).fetch("results").first(MAX_RESULTS).map { |result| candidate(result) }
    rescue JSON::ParserError, KeyError, NoMethodError => e
      raise Error, "réponse de Pl@ntNet illisible (#{e.class})"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error, "Pl@ntNet injoignable (#{e.class})"
    end

    private

    def candidate(result)
      species = result.fetch("species")
      Candidate.new(
        latin_name: species.fetch("scientificNameWithoutAuthor"),
        authorship: species["scientificNameAuthorship"].presence,
        common_names: Array(species["commonNames"]).compact_blank,
        genus: species.dig("genus", "scientificNameWithoutAuthor"),
        family: species.dig("family", "scientificNameWithoutAuthor"),
        score: result.fetch("score").to_f,
        gbif_id: result.dig("gbif", "id")&.to_s
      )
    end

    def post(images)
      uri = ENDPOINT.dup
      uri.query = URI.encode_www_form("api-key" => @api_key, "lang" => "fr", "nb-results" => MAX_RESULTS,
                                      "include-related-images" => "false")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      boundary = "plantnet-#{SecureRandom.hex(12)}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = multipart(images, boundary)
      http.request(request)
    end

    # Le corps multipart écrit à la main plutôt que `set_form` : une chaîne
    # (et non un flux) se relit dans les specs. « auto » : Pl@ntNet devine
    # lui-même l'organe de chaque photo (feuille, fleur…) — on ne demande rien
    # de plus à qui est au pied de l'arbre.
    def multipart(images, boundary)
      body = +"".b
      images.each do |image|
        filename = image[:filename].to_s.gsub(/["\r\n]/, "_")
        body << "--#{boundary}\r\n"
        body << %(Content-Disposition: form-data; name="images"; filename="#{filename}"\r\n).b
        body << "Content-Type: #{image[:content_type]}\r\n\r\n"
        body << image[:io].read.b << "\r\n"
        body << "--#{boundary}\r\n"
        body << %(Content-Disposition: form-data; name="organs"\r\n\r\nauto\r\n)
      end
      body << "--#{boundary}--\r\n"
    end
  end
end
