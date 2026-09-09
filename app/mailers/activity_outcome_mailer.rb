class ActivityOutcomeMailer < ApplicationMailer
  # Rappel au porteur : ses activités passées qui n'ont pas encore dit si elles
  # ont eu lieu (epic #244, phase 2).
  #
  # Chaque ligne porte DEUX liens à jeton signé, à portée d'une seule
  # réservation : « a eu lieu » mène à une page de confirmation qui POSTe (jamais
  # de mutation sur un GET, que les antivirus de messagerie préchargent), « n'a
  # pas eu lieu » exige une connexion et renvoie vers l'écran admin.
  def reminder(human, bookings)
    @human = human
    @bookings = bookings
    @host = ENV.fetch("APPLICATION_HOST", "app.les4sources.be")

    return if human.email.blank?

    mail(to: human.email,
         subject: "#{bookings.size} activité#{'s' if bookings.size > 1} à confirmer — ont-elles eu lieu ?")
  end
end
