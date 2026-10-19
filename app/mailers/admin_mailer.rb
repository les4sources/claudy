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

  # Le client a cliqué « J'ai envoyé le virement » sur la page de son séjour
  # (Michael, 2026-10-19). Même destinataires que le paiement Stripe ; la
  # réponse va au client, pour lui écrire si le virement n'arrive pas.
  def transfer_announced(stay)
    @stay = StayDecorator.new(stay)
    @amount = ActiveSupport::NumberHelper.number_to_currency(stay.transfer_notified_cents.to_i / 100.0)
    @client = ActionView::Base.full_sanitizer.sanitize(@stay.display_name.to_s).squish.presence || "Client inconnu"
    @dates = ActionView::Base.full_sanitizer.sanitize(@stay.date_range.to_s).squish.presence
    mail(
      from: "sejours@les4sources.be",
      to: "compta@les4sources.be",
      cc: "sejours@les4sources.be",
      reply_to: stay.customer&.email.presence,
      subject: "🏦 Virement annoncé : #{@amount} — #{[@client, @dates].compact.join(" · ")}",
      tag: "admin_transfer_announced",
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
