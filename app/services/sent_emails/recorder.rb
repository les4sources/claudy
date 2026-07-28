module SentEmails
  # Transforme un `Mail::Message` fraîchement livré en lignes de `SentEmail`.
  #
  # Règle de périmètre : on ne journalise QUE les destinataires `to` qui
  # correspondent à un client existant. Le bcc d'archivage
  # (`ApplicationMailer.default bcc:`), les notifications à l'équipe et les
  # emails aux porteurs d'activité ne créent donc aucune ligne.
  class Recorder
    def self.record(message)
      new(message).record
    end

    def initialize(message)
      @message = message
    end

    # @return [Array<SentEmail>] les lignes créées (vide si aucun destinataire
    #   ne correspond à un client, ou si l'email est déjà journalisé).
    def record
      Array(@message.to).filter_map { |address| record_for(address) }
    end

    private

    def record_for(address)
      email = Customer.normalize_email(address)
      return if email.blank?

      customer = Customer.find_by(email: email)
      return if customer.nil?

      # Le backfill Postmark peut avoir déjà importé ce message (ou l'inverse) :
      # le MessageID Postmark tranche.
      return if postmark_message_id.present? &&
                SentEmail.exists?(postmark_message_id: postmark_message_id)

      SentEmail.create!(
        customer: customer,
        to_email: email,
        subject: @message.subject,
        body_html: html_body,
        body_text: text_body,
        mailer: mailer_name,
        tag: header_value("TAG"),
        postmark_message_id: postmark_message_id,
        sent_at: Time.current,
        source: "app"
      )
    end

    def html_body
      part = @message.html_part
      return part.body.decoded if part
      return @message.body.decoded if @message.mime_type == "text/html"

      nil
    end

    def text_body
      part = @message.text_part
      return part.body.decoded if part
      return @message.body.decoded if @message.mime_type == "text/plain"

      nil
    end

    # Postmark repose l'identifiant du message livré dans un en-tête
    # (`Postmark::ApiClient#update_message`). Absent en test/dev où la livraison
    # ne passe pas par l'API.
    def postmark_message_id
      @postmark_message_id ||= header_value("X-PM-Message-Id")
    end

    # `delivery_handler` est la classe du mailer, posée par ActionMailer au
    # moment du `mail(...)` (`wrap_delivery_behavior`).
    def mailer_name
      handler = @message.delivery_handler
      handler.is_a?(Class) ? handler.name : nil
    end

    def header_value(name)
      field = @message[name]
      return nil if field.nil?

      field.value.presence
    end
  end
end
