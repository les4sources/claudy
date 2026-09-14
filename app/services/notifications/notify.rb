module Notifications
  # Point de création UNIQUE d'une notification (epic #242, décision 2).
  #
  # Passer par ici, et nulle part ailleurs, garantit trois choses ensemble :
  # la ligne en base, l'email si le destinataire le veut, et la trace de
  # l'envoi (`emailed_at`). Un `Notification.create` posé à la main quelque part
  # dans un contrôleur rendrait l'une des trois facultative.
  #
  # On ne se notifie jamais soi-même : `actor == recipient` est ignoré
  # silencieusement, ce qui évite à chaque appelant de refaire ce test.
  #
  # L'email ne fait JAMAIS échouer l'appel : la notification est le fait qui
  # compte, l'email n'en est que la copie. Un SMTP fâché ne doit pas empêcher la
  # cloche de s'allumer.
  class Notify < ServiceBase
    attr_reader :notification

    def initialize(recipient:, kind:, title:, url:, body: nil, actor: nil, notifiable: nil)
      @recipient  = recipient
      @kind       = kind.to_s
      @title      = title
      @url        = url
      @body       = body
      @actor      = actor
      @notifiable = notifiable
      @report_errors = true
    end

    def run
      catch_error(context: { kind: @kind, recipient_id: @recipient&.id }) { run! }
    end

    def run!
      return false if skip?

      @notification = Notification.create!(
        recipient: @recipient, actor: @actor, kind: @kind,
        notifiable: @notifiable, title: @title, body: @body, url: @url
      )

      deliver_email
      true
    end

    # Notifie plusieurs destinataires d'un coup. Rend les notifications
    # réellement créées — les destinataires ignorés (auteur lui-même, doublons,
    # nil) n'y figurent pas.
    def self.broadcast(recipients:, **attrs)
      Array(recipients).compact.uniq.filter_map do |recipient|
        service = new(recipient: recipient, **attrs)
        service.notification if service.run
      end
    end

    private

    def skip?
      return true if @recipient.blank?
      return true if @actor.present? && @actor.id == @recipient.id

      false
    end

    # `emailed_at` n'est posé QUE si l'email est parti. Une préférence à faux ou
    # un destinataire sans adresse laissent le champ vide : c'est ce qui permet
    # de relire l'historique et de savoir ce qui a vraiment été envoyé.
    def deliver_email
      return unless @recipient.notify_by_email?
      return if @recipient.email.blank?

      NotificationMailer.notify(@notification).deliver_later
      @notification.update_column(:emailed_at, Time.current)
    rescue StandardError => e
      # L'email est la copie, pas le fait. On trace et on continue.
      Sentry.capture_exception(e) if defined?(Sentry)
      Rails.logger.warn("Notifications::Notify — email non envoyé : #{e.class} #{e.message}")
    end
  end
end
