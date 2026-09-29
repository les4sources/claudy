require "net/http"
require "resolv"
require "ipaddr"

module Events
  # Télécharge l'image d'un événement depuis une URL (API agent : `image_url`).
  #
  # Garde-fous : HTTPS uniquement, jamais vers une adresse privée ou locale
  # (l'URL vient d'un appelant, le serveur ne doit pas servir de relais vers le
  # réseau interne), trois redirections au plus, 15 Mo au plus, et une réponse
  # qui se déclare image. Toute entorse lève `Error`, avec un message lisible.
  class RemoteImage
    class Error < StandardError; end

    MAX_BYTES = 15.megabytes
    MAX_REDIRECTS = 3
    TIMEOUT = 15

    Download = Struct.new(:io, :filename, :content_type)

    def initialize(url)
      @url = url.to_s.strip
    end

    def fetch(url = @url, redirects_left = MAX_REDIRECTS)
      uri = parse(url)
      response = request(uri)

      case response
      when Net::HTTPRedirection
        raise Error, "trop de redirections" if redirects_left.zero?

        fetch(URI.join(uri.to_s, response["location"].to_s).to_s, redirects_left - 1)
      when Net::HTTPSuccess
        build(uri, response)
      else
        raise Error, "le serveur a répondu #{response.code}"
      end
    end

    private

    def parse(url)
      uri = URI.parse(url)
      raise Error, "attendu une URL https://" unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise Error, "adresse privée ou locale refusée" if private_host?(uri.host)

      uri
    rescue URI::InvalidURIError
      raise Error, "URL invalide"
    end

    def private_host?(host)
      addresses = Resolv.getaddresses(host)
      raise Error, "hôte introuvable : #{host}" if addresses.empty?

      addresses.any? do |address|
        ip = IPAddr.new(address)
        ip.private? || ip.loopback? || ip.link_local? || address == "0.0.0.0" || address == "::"
      end
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    rescue SocketError, Timeout::Error, OpenSSL::SSL::SSLError, SystemCallError => e
      raise Error, "téléchargement impossible (#{e.class.name.demodulize})"
    end

    def build(uri, response)
      content_type = response["content-type"].to_s.split(";").first.to_s.strip.downcase
      raise Error, "la réponse n'est pas une image (#{content_type.presence || 'type inconnu'})" unless content_type.start_with?("image/")

      body = response.body.to_s
      raise Error, "image vide" if body.empty?
      raise Error, "image trop lourde (15 Mo au plus)" if body.bytesize > MAX_BYTES

      Download.new(StringIO.new(body), filename_for(uri, content_type), content_type)
    end

    def filename_for(uri, content_type)
      name = File.basename(URI.decode_www_form_component(uri.path.to_s))
      return name if name.present? && name.include?(".")

      "image.#{Rack::Mime::MIME_TYPES.invert[content_type]&.delete_prefix('.') || 'jpg'}"
    end
  end
end
