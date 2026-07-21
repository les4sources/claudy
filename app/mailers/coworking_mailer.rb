# Emails du coworking (epic #126, Phase 3). Sobres, cohérents avec les autres
# mailers : un fait par email, aucune donnée superflue.
class CoworkingMailer < ApplicationMailer
  # Confirmation d'achat d'un pack : montant, nombre de journées, expiration.
  # Déclenché par le webhook Stripe au moment où le pack devient payé.
  def pack_purchased(pack)
    @pack = pack
    @customer = pack.customer
    @amount = Money.new(pack.price_cents, "EUR").format
    return if @customer.email.blank?

    mail(to: @customer.email, subject: "Votre pack de coworking aux 4 Sources")
  end

  # Confirmation d'une journée réservée.
  def reservation_confirmed(reservation)
    @reservation = reservation
    @customer = reservation.customer
    return if @customer.email.blank?

    mail(to: @customer.email, subject: "Journée de coworking réservée — Les 4 Sources")
  end

  # Confirmation d'une journée annulée.
  def reservation_cancelled(reservation)
    @reservation = reservation
    @customer = reservation.customer
    return if @customer.email.blank?

    mail(to: @customer.email, subject: "Journée de coworking annulée — Les 4 Sources")
  end
end
