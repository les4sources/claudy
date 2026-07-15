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
    mail(
      to: stay.customer.email,
      subject: "Votre demande de réservation aux 4 Sources"
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
