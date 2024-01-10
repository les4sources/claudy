class BookingMailer < ApplicationMailer
  def booking_canceled(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Votre réservation aux 4 Sources est annulée",
      tag: "booking_canceled"
    )
  end

  def booking_confirmed(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Votre réservation aux 4 Sources est confirmée 👍",
      tag: "booking_confirmed"
    )
  end

  def booking_declined(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Votre réservation aux 4 Sources ne peut pas être confirmée",
      tag: "booking_declined"
    )
  end

  def booking_details(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Votre réservation aux 4 Sources",
      tag: "booking_details"
    )
  end

  # def booking_paid(booking)
  #   @booking = booking
  #   mail(
  #     to: booking.email,
  #     subject: "Nous avons reçu votre paiement 🧾",
  #     tag: "booking_paid"
  #   )
  # end

  def booking_partially_paid(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Nous avons reçu votre paiement partiel 🧾",
      tag: "booking_partially_paid"
    )
  end

  def booking_request(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Confirmation de votre demande de réservation aux 4 Sources",
      tag: "booking_request"
    )
  end

  def booking_request_rejected(booking)
    @booking = booking
    mail(
      to: booking.email,
      subject: "Votre réservation aux 4 Sources ne peut pas être confirmée",
      tag: "booking_request_rejected"
    )
  end
end