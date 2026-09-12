# La copie par email d'une notification (epic #242, phase 2).
#
# Un seul gabarit pour tous les `kind` : la notification porte déjà son titre,
# son corps court et son adresse. Ajouter un `kind` ne demande donc jamais un
# nouveau mailer — c'est le point de la décision 2.
class NotificationMailer < ApplicationMailer
  def notify(notification)
    @notification = notification
    @recipient    = notification.recipient
    @host         = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")

    return if @recipient.email.blank?

    mail(to: @recipient.email, subject: notification.title)
  end
end
