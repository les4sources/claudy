module SiteStats
  # Transforme une requête en `SiteHit`, sans rien garder qui identifie le
  # visiteur au-delà de la journée.
  #
  # L'empreinte `visitor_hash` = SHA-256(sel du jour + IP + User-Agent). Le sel
  # change chaque jour et l'ancien est détruit (`SiteVisitSalt`) : l'empreinte
  # suffit à compter les visiteurs d'une journée et à relier une visite du site
  # à une demande de réservation le même jour, puis devient inexploitable. L'IP
  # et le User-Agent ne sont jamais écrits en base.
  #
  # `record` ne lève jamais : un robot, un membre connecté à Claudy ou une
  # donnée invalide renvoient `nil` et rien n'est écrit.
  class Tracker
    SITE_HOSTS = %w[www.les4sources.be les4sources.be].freeze

    BOT_PATTERN = /bot|crawl|spider|slurp|scrape|headless|lighthouse|pagespeed|preview|facebookexternalhit|
                   embedly|quora|whatsapp|telegram|curl|wget|python|httpclient|axios|node-fetch|go-http|
                   java\/|okhttp|monitor|uptime|pingdom|phantom|selenium|puppeteer|playwright/ix

    # Sources reconnues, de la plus précise à la plus large : Gemini avant Google.
    SOURCES = [
      [/(\A|\.)gemini\.google\.com\z/, "Gemini"],
      [/(\A|\.)mail\.google\.com\z/, "Gmail"],
      [/(\A|\.)google\.[a-z.]+\z/, "Google"],
      [/(\A|\.)bing\.com\z/, "Bing"],
      [/(\A|\.)duckduckgo\.com\z/, "DuckDuckGo"],
      [/(\A|\.)ecosia\.org\z/, "Ecosia"],
      [/(\A|\.)qwant\.com\z/, "Qwant"],
      [/(\A|\.)yahoo\.[a-z.]+\z/, "Yahoo"],
      [/(\A|\.)(facebook\.com|fb\.com|fb\.me)\z/, "Facebook"],
      [/(\A|\.)instagram\.com\z/, "Instagram"],
      [/(\A|\.)(linkedin\.com|lnkd\.in)\z/, "LinkedIn"],
      [/(\A|\.)(t\.co|x\.com|twitter\.com)\z/, "X (Twitter)"],
      [/(\A|\.)(youtube\.com|youtu\.be)\z/, "YouTube"],
      [/(\A|\.)(chatgpt\.com|chat\.openai\.com)\z/, "ChatGPT"],
      [/(\A|\.)perplexity\.ai\z/, "Perplexity"],
      [/(\A|\.)claude\.ai\z/, "Claude"],
      [/(\A|\.)app\.les4sources\.be\z/, "Claudy"],
      [/(\A|\.)semisto\.org\z/, "Semisto"]
    ].freeze

    def initialize(request)
      @request = request
    end

    def bot?
      user_agent.blank? || user_agent.match?(BOT_PATTERN)
    end

    # Un membre connecté à Claudy qui regarde le site ne compte pas. On ne lit
    # la session que si son cookie est présent : chez un visiteur, rien n'est
    # chargé, donc rien ne peut être (ré)écrit.
    def member?
      return false if @request.cookies["_claudy_session"].blank?

      @request.env["warden"]&.user(:user).present?
    rescue StandardError
      false
    end

    # kind/name : le type de hit ; url : l'adresse complète de la page (pour le
    # chemin et les paramètres utm_*) ; referrer : document.referrer ; target :
    # la destination d'un clic sortant ou l'identifiant d'un formulaire.
    def record(kind:, name: nil, url: nil, path: nil, referrer: nil, target: nil)
      return nil if bot? || member?

      page = parse_url(url)
      path = normalize_path(path || page&.path)
      return nil if path.nil?

      now = Time.current
      referrer_host = external_referrer_host(referrer)
      utm = utm_params(page)

      SiteHit.create!(
        occurred_at: now,
        day: now.to_date,
        kind: kind,
        name: name.presence,
        path: path,
        target: clean_target(target),
        visitor_hash: visitor_hash(now.to_date),
        referrer_host: referrer_host,
        source: source_for(referrer_host, utm[:utm_source], referrer),
        **utm,
        device: device,
        browser: browser,
        os: os,
        country: country
      )
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def visitor_hash(day)
      Digest::SHA256.hexdigest([SiteVisitSalt.for(day), client_ip, user_agent].join("|"))
    end

    # Cloudflare est devant Hatchbox : l'adresse du visiteur arrive dans
    # CF-Connecting-IP, `remote_ip` ne verrait que le relais Cloudflare.
    def client_ip
      @request.headers["CF-Connecting-IP"].presence || @request.remote_ip
    end

    def device
      case user_agent
      when /iPad|Tablet|Android(?!.*Mobile)/i then "Tablette"
      when /Mobi|iPhone|iPod|Android/i then "Mobile"
      else "Ordinateur"
      end
    end

    def browser
      case user_agent
      when /Edg(e|A|iOS)?\//i then "Edge"
      when /OPR\/|Opera/i then "Opera"
      when /SamsungBrowser/i then "Samsung Internet"
      when /Firefox\/|FxiOS/i then "Firefox"
      when /Chrome\/|CriOS/i then "Chrome"
      when /Safari\//i then "Safari"
      else "Autre"
      end
    end

    def os
      case user_agent
      when /iPhone|iPad|iPod/i then "iOS"
      when /Android/i then "Android"
      when /Windows/i then "Windows"
      when /CrOS/i then "ChromeOS"
      when /Mac OS X|Macintosh/i then "macOS"
      when /Linux/i then "Linux"
      else "Autre"
      end
    end

    # Pays deviné par Cloudflare à partir de l'IP (XX = inconnu, T1 = Tor).
    def country
      code = @request.headers["CF-IPCountry"].to_s.upcase
      code.match?(/\A[A-Z]{2}\z/) && !%w[XX T1].include?(code) ? code : nil
    end

    private

    def user_agent
      @user_agent ||= @request.user_agent.to_s
    end

    def parse_url(url)
      return nil if url.blank?

      URI.parse(url.to_s.strip)
    rescue URI::InvalidURIError
      nil
    end

    # Le chemin seul, sans paramètres ni ancre, sans slash final (comme les
    # URLs du site), borné à 300 caractères.
    def normalize_path(path)
      path = path.to_s.split(/[?#]/).first.to_s
      return nil unless path.start_with?("/") && !path.match?(/\s/)

      path = path.chomp("/") while path.length > 1 && path.end_with?("/")
      path[0, 300]
    end

    def external_referrer_host(referrer)
      host = parse_url(referrer)&.host&.downcase
      return nil if host.blank? || SITE_HOSTS.include?(host)

      host.delete_prefix("www.")[0, 120]
    end

    # Sans référent externe : une campagne (utm_source) si le lien en porte une,
    # « Accès direct » si le visiteur arrive de nulle part, rien du tout s'il
    # navigue d'une page du site à l'autre.
    def source_for(referrer_host, utm_source, referrer)
      if referrer_host
        SOURCES.find { |pattern, _| referrer_host.match?(pattern) }&.last || referrer_host
      elsif utm_source.present?
        utm_source
      elsif referrer.blank?
        "Accès direct"
      end
    end

    def utm_params(page)
      query = Rack::Utils.parse_query(page&.query.to_s)
      %w[utm_source utm_medium utm_campaign].to_h do |key|
        [key.to_sym, query[key].is_a?(String) ? query[key].strip.downcase.presence&.slice(0, 100) : nil]
      end
    rescue StandardError
      { utm_source: nil, utm_medium: nil, utm_campaign: nil }
    end

    # Une destination sans ses paramètres : on veut savoir vers où, pas avec quoi.
    def clean_target(target)
      return nil if target.blank?

      target.to_s.split(/[?#]/).first.to_s.strip[0, 300].presence
    end
  end
end
