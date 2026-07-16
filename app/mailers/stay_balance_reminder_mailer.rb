class StayBalanceReminderMailer < ApplicationMailer
  # Relance de paiement du solde exigible ~14 jours avant l'arrivée (epic #55,
  # Phase 5). Purement incitative : AUCUNE réservation n'est bloquée ni annulée.
  # Le lien pointe vers la page séjour à jeton où le client règle le solde
  # (Phase 3). L'hôte des liens est résolu comme dans ActivitySelectionMailer,
  # pour rester stable en test comme en prod.
  def reminder(stay)
    @stay = stay
    @balance = Money.new(stay.balance_due_cents, "EUR")
    @stay_url = public_stay_url(stay.token,
                                host: ENV.fetch("APPLICATION_HOST", "app.les4sources.be"))
    mail(
      to: stay.customer.email,
      subject: "Il reste un solde à régler pour votre séjour aux 4 Sources"
    )
  end
end
