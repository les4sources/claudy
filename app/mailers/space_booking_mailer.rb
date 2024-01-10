class SpaceBookingMailer < ApplicationMailer
  def space_booking_canceled(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Votre réservation d'espaces aux 4 Sources est annulée",
      tag: "space_booking_canceled"
    )
  end

  def space_booking_confirmed(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Votre réservation d'espaces aux 4 Sources est confirmée 👍",
      tag: "space_booking_confirmed"
    )
  end

  def space_booking_declined(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Votre réservation d'espaces aux 4 Sources ne peut pas être confirmée",
      tag: "space_booking_declined"
    )
  end

  def space_booking_details(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Votre réservation d'espaces aux 4 Sources",
      tag: "space_booking_details"
    )
  end

  # def space_booking_paid(space_booking)
  #   @space_booking = space_booking
  #   mail(
  #     to: space_booking.email,
  #     subject: "Nous avons reçu votre paiement 🧾",
  #     tag: "space_booking_paid"
  #   )
  # end

  def space_booking_partially_paid(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Nous avons reçu votre paiement partiel 🧾",
      tag: "space_booking_partially_paid"
    )
  end

  def space_booking_request(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Confirmation de votre demande de réservation d'espaces aux 4 Sources",
      tag: "space_booking_request"
    )
  end

  def space_booking_request_rejected(space_booking)
    @space_booking = space_booking
    mail(
      to: space_booking.email,
      subject: "Votre réservation d'espaces aux 4 Sources ne peut pas être confirmée",
      tag: "space_booking_request_rejected"
    )
  end
end