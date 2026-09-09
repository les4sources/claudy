module Kitchen
  # Qui prévenir, de quoi, et quand (epic #219, phase 4).
  #
  # Deux règles tiennent tout : **aucun email ne part jamais vers le client** —
  # Malau écrit ses mails elle-même — et le responsable est prévenu de chaque
  # événement qui le concerne, tandis que la coordination n'entend parler que
  # des refus et des désistements.
  #
  # Le notifier lit ce que la sauvegarde a RÉELLEMENT changé (`previous_changes`)
  # plutôt que l'état courant : c'est la seule façon de distinguer « le client
  # vient de confirmer » de « on a re-enregistré une ligne déjà confirmée ».
  class Notifier
    def initialize(order:, changes: {})
      @order   = order
      @changes = changes || {}
    end

    def call
      mailer = mailer_for
      return if mailer.nil?

      deliver(mailer)
    end

    # Le destinataire NORMAL d'une ligne : la personne qui s'en charge, ou à
    # défaut la responsable par défaut de la famille. Exposé en méthode de
    # classe pour que la notification groupée (issue #266) range ses lignes par
    # la même règle, sans la redire.
    def self.responsible_email_for(order)
      (order.responsible_human || Kitchen::Config.default_human(order.family))&.email
    end

    private

    attr_reader :order, :changes

    def created? = changes.key?("id")

    def changed_to(field, value)
      before, after = changes[field]
      after.to_s == value && before.to_s != value
    end

    # Un seul email par sauvegarde, dans l'ordre de ce qui compte le plus.
    def mailer_for
      return :new_request if created?
      return :cancelled if changed_to("status", "cancelled")
      return :refused   if changed_to("validation", "refused")
      # Plus rien ne part d'une ligne annulée : elle est sortie du jeu.
      return nil if order.cancelled?
      return :confirmed if changed_to("status", "confirmed")
      return revalidation_mailer if reopened_by_change?

      nil
    end

    # La validation est retombée en attente sans que personne ne l'ait demandée :
    # c'est le callback du modèle, donc la prestation a changé.
    def reopened_by_change?
      before, after = changes["validation"]
      before.to_s == "accepted" && after.to_s == "pending"
    end

    # Pour un repas, il faut un nouvel accord de Stéphanie. Pour un buffet ou un
    # apéro, celui qui s'en charge s'en charge toujours : on l'informe, on ne lui
    # redemande rien.
    def revalidation_mailer = order.family == "repas" ? :revalidation_needed : :changed

    # Le refus et le désistement vont à la coordination ; tout le reste au
    # responsable, ou à défaut au responsable par défaut de la famille.
    def recipient_for(mailer)
      return Kitchen::Config.coordinator_email if mailer == :refused

      self.class.responsible_email_for(order)
    end

    def deliver(mailer)
      recipient = recipient_for(mailer)
      if recipient.blank?
        Rails.logger.info("[Kitchen::Notifier] #{mailer} sans destinataire pour MealOrder ##{order.id}")
        return
      end

      KitchenMailer.public_send(mailer, order, recipient).deliver_later
    end
  end
end
