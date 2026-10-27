module SentEmails
  # Applique une notification Amazon SES (le `Message` d'une notification SNS,
  # déjà vérifiée par `Webhooks::SesNotificationsController`) au journal des
  # emails envoyés.
  #
  # Seuls les rebonds et les plaintes laissent une trace : la ligne
  # `SentEmail` du destinataire concerné prend son `delivery_issue`. Les autres
  # types (Delivery…) et les emails non journalisés (équipe, porteurs) ne
  # touchent à rien. SES tient de son côté sa liste de suppression : une
  # adresse en rebond définitif n'est plus tentée.
  #
  #   SentEmails::SesFeedback.new(JSON.parse(sns["Message"])).apply
  class SesFeedback
    def initialize(notification)
      @notification = notification
    end

    # @return [Integer] le nombre de lignes mises à jour.
    def apply
      issue, recipients = feedback
      return 0 if issue.nil? || message_id.blank?

      recipients.sum do |recipient|
        address = Customer.normalize_email(recipient["emailAddress"])
        next 0 if address.blank?

        SentEmail.where(ses_message_id: message_id, to_email: address).update_all(
          delivery_issue: issue,
          delivery_issue_detail: detail_for(recipient)&.truncate(255),
          delivery_issue_at: occurred_at,
          updated_at: Time.current
        )
      end
    end

    private

    # Les notifications de l'identité portent `notificationType`, celles d'un
    # configuration set `eventType` : même contenu, on accepte les deux.
    def type
      @notification["notificationType"] || @notification["eventType"]
    end

    def feedback
      case type
      when "Bounce"
        bounce = @notification["bounce"] || {}
        issue = bounce["bounceType"] == "Permanent" ? "bounce" : "soft_bounce"
        [issue, Array(bounce["bouncedRecipients"])]
      when "Complaint"
        ["complaint", Array(@notification.dig("complaint", "complainedRecipients"))]
      end
    end

    def detail_for(recipient)
      return @notification.dig("complaint", "complaintFeedbackType") if type == "Complaint"

      recipient["diagnosticCode"].presence ||
        [@notification.dig("bounce", "bounceType"), @notification.dig("bounce", "bounceSubType")].compact.join(" / ").presence
    end

    def occurred_at
      raw = @notification.dig("bounce", "timestamp") || @notification.dig("complaint", "timestamp")
      Time.zone.parse(raw.to_s) || Time.current
    rescue ArgumentError
      Time.current
    end

    def message_id
      @notification.dig("mail", "messageId")
    end
  end
end
