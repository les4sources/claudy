class AdminMailer < ApplicationMailer
  def booking_request(booking)
    @booking = booking
    mail(
      to: "reservation@les4sources.be",
      subject: "Demande de réservation pour un hébergement: #{@booking.name}",
      tag: "admin_booking_request"
    )
  end
end