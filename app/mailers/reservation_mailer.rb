class ReservationMailer < ApplicationMailer
  # Récap post-réservation avec lien token stable de consultation (AC-T2-21).
  # Le breakdown affiché provient du même PricingModel.quote que l'UI (source
  # unique — AC-T2-17), recalculé depuis le Stay persisté.
  def confirmation_request(stay)
    @stay = stay
    @booking = stay.bookables.find { |b| b.is_a?(Booking) }
    # Stay-first (epic #26, Phase 2) : le lien de consultation envoyé au client
    # pointe sur la page séjour, pas sur la page booking — un séjour sans
    # hébergement n'a d'ailleurs pas de booking.
    @token = stay.token
    @quote = quote_from(stay)
    # L'acompte confirme la réservation : cet email est aussi le filet de
    # rattrapage si le client a quitté la page Stripe sans payer — il porte
    # donc le montant et un lien de paiement direct tant que l'acompte est dû.
    @pending_deposit = stay.payments.pending.where(payment_method: "card")
                           .order(:created_at).first
    mail(
      to: stay.customer.email,
      subject: "Votre demande de réservation aux 4 Sources"
    )
  end

  # Second email du flux (décision 2026-07-20) : envoyé par le webhook Stripe
  # au PREMIER encaissement d'un séjour encore `pending` — « acompte bien reçu,
  # notre équipe valide votre demande ». Le solde d'un séjour confirmé ne passe
  # jamais ici (voir Stripe::CompletedCheckoutService).
  def deposit_received(payment)
    @payment = payment
    @stay = payment.stay
    @token = @stay.token
    mail(
      to: @stay.customer.email,
      subject: "Acompte bien reçu — votre réservation aux 4 Sources"
    )
  end

  private

  def quote_from(stay)
    draft = Reservations::Draft.new(
      lodging_id: @booking&.lodging_id,
      arrival_date: stay.arrival_date,
      departure_date: stay.departure_date
    )
    draft.quote
  rescue StandardError
    nil
  end
end
