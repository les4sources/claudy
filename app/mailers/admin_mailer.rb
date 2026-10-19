class AdminMailer < ApplicationMailer
  def booking_request(booking)
    @booking = booking
    mail(
      from: "sejours@les4sources.be",
      to: "sejours@les4sources.be",
      subject: "💁‍♂️ DEMANDE DE RÉSERVATION pour un hébergement: #{@booking.name}",
      tag: "admin_booking_request",
      bcc: nil
    )
  end

  def booking_canceled(booking)
    @booking = BookingDecorator.new(booking)
    mail(
      from: "sejours@les4sources.be",
      to: "sejours@les4sources.be",
      subject: "⚠️ Réservation d'hébergement annulée: #{ActionView::Base.full_sanitizer.sanitize(@booking.group_or_name)} (#{@booking.date_range})",
      tag: "admin_booking_canceled",
      bcc: nil
    )
  end

  # Paiement en ligne (Stripe) encaissé : la compta d'abord, l'accueil en copie
  # (Michael 2026-10-19). L'objet dit montant, client et dates.
  def payment_received(payment)
    @payment = PaymentDecorator.new(payment)
    @stay = payment.stay
    mail(
      from: "sejours@les4sources.be",
      to: "compta@les4sources.be",
      cc: "sejours@les4sources.be",
      subject: payment_received_subject,
      tag: "admin_payment_received",
      bcc: nil
    )
  end

  def space_booking_canceled(space_booking)
    @space_booking = SpaceBookingDecorator.new(space_booking)
    mail(
      from: "sejours@les4sources.be",
      to: "sejours@les4sources.be",
      subject: "⚠️ Réservation d'espaces annulée: #{ActionView::Base.full_sanitizer.sanitize(@space_booking.group_or_name)} (#{@space_booking.date_range})",
      tag: "admin_space_booking_canceled",
      bcc: nil
    )
  end

  private

  def payment_received_subject
    details = [@payment.admin_client_label, @payment.admin_dates_label].compact.join(" · ")
    "💳 Paiement reçu : #{@payment.amount} — #{details}"
  end
end
