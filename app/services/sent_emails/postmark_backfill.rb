module SentEmails
  # Rapatrie l'historique des emails déjà envoyés depuis l'API Postmark
  # (« Outbound message search » + détail du message pour le corps).
  #
  # Postmark ne conserve le CONTENU des messages qu'environ 45 jours : au-delà,
  # la recherche renvoie encore les métadonnées mais le corps revient vide. Le
  # journal local (`SentEmails::Observer`) prend le relais pour la suite.
  #
  # Dédoublonnage sur `postmark_message_id` : rejouer le backfill est sans
  # effet, et un email déjà journalisé à l'envoi n'est jamais ré-importé.
  #
  #   SentEmails::PostmarkBackfill.new(days: 45).run
  #   # => { scanned: 312, imported: 118, skipped: 40, unmatched: 154 }
  class PostmarkBackfill
    PAGE_SIZE = 100

    attr_reader :stats

    def initialize(days: 45, limit: 2000, throttle: 0.1, dry_run: false, client: nil, logger: Rails.logger)
      @days = days.to_i
      @limit = limit.to_i
      @throttle = throttle.to_f
      @dry_run = dry_run
      @client = client
      @logger = logger
      @stats = { scanned: 0, imported: 0, skipped: 0, unmatched: 0, without_body: 0 }
    end

    def run
      offset = 0

      loop do
        count = [PAGE_SIZE, @limit - @stats[:scanned]].min
        break if count <= 0

        messages = fetch_page(offset: offset, count: count)
        break if messages.blank?

        # `first(count)` : le plafond reste tenu même si l'API renvoie plus que
        # la page demandée.
        messages = messages.first(count)
        messages.each { |message| process(message) }

        offset += messages.size
        break if messages.size < count
      end

      log("backfill terminé : #{@stats.inspect}")
      @stats
    end

    private

    def client
      @client ||= Postmark::ApiClient.new(ENV.fetch("POSTMARK_API_TOKEN"))
    end

    def fetch_page(offset:, count:)
      Array(client.get_messages(offset: offset, count: count, fromdate: @days.days.ago.to_date.to_s))
    end

    def process(message)
      @stats[:scanned] += 1

      message_id = fetch(message, :message_id)
      customers = matching_customers(message)

      if customers.empty?
        @stats[:unmatched] += 1
        return
      end

      if message_id.present? && SentEmail.exists?(postmark_message_id: message_id)
        @stats[:skipped] += 1
        return
      end

      details = message_details(message_id)
      html_body = fetch(details, :html_body)
      text_body = fetch(details, :text_body)
      @stats[:without_body] += 1 if html_body.blank? && text_body.blank?

      customers.each_with_index do |(customer, email), index|
        next if @dry_run

        SentEmail.create!(
          customer: customer,
          to_email: email,
          subject: fetch(message, :subject),
          body_html: html_body.presence,
          body_text: text_body.presence,
          mailer: nil,
          tag: fetch(message, :tag).presence,
          # Un même message adressé à deux clients donnerait deux lignes portant
          # le même MessageID, que l'index unique refuse : seule la première le
          # porte (en pratique nos mailers n'écrivent qu'à un client à la fois).
          postmark_message_id: (message_id if index.zero?),
          sent_at: parse_time(fetch(message, :received_at)),
          source: "postmark"
        )
      end

      @stats[:imported] += 1
      sleep(@throttle) if @throttle.positive?
    end

    def message_details(message_id)
      return {} if message_id.blank?

      client.get_message(message_id)
    rescue Postmark::Error => e
      log("détail indisponible pour #{message_id} : #{e.class} #{e.message}")
      {}
    end

    # Seuls les destinataires `to` comptent : le bcc d'archivage et les copies
    # internes ne sont pas l'historique DU client.
    def matching_customers(message)
      Array(fetch(message, :to)).filter_map do |recipient|
        email = Customer.normalize_email(address_of(recipient))
        next if email.blank?

        customer = Customer.find_by(email: email)
        [customer, email] if customer
      end
    end

    def address_of(recipient)
      case recipient
      when Hash  then recipient[:email] || recipient["Email"]
      when String then recipient
      end
    end

    # Les réponses Postmark ont leurs clés de premier niveau en symboles
    # underscore, mais les structures imbriquées gardent le CamelCase d'origine.
    def fetch(hash, key)
      return nil if hash.blank?

      hash[key] || hash[key.to_s] || hash[key.to_s.camelize] || hash[key.to_s.camelize.to_sym]
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError
      Time.current
    end

    def log(message)
      @logger&.info("[SentEmails::PostmarkBackfill] #{message}")
    end
  end
end
