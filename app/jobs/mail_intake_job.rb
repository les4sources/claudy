# Le bouton « Relever maintenant » de « Pièces reçues » : un passage complet
# hors requête, le temps d'IMAP et de Jev ne doit pas faire attendre la page.
class MailIntakeJob < ApplicationJob
  queue_as :default

  def perform
    MailIntake::Run.new.run!
  end
end
