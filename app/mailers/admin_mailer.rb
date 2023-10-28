class AdminMailer < ApplicationMailer
  def booking_request(booking)
    @booking = booking
    mail(
      to: "reservation@les4sources.be",
      subject: "Demande de réservation pour un hébergement: #{@booking.name}",
      tag: "admin_booking_request"
    )
  end

  def booking_canceled(booking)
    @booking = BookingDecorator.new(booking)
    mail(
      to: "reservation@les4sources.be",
      subject: "⚠️ Réservation d'hébergement annulée: #{@booking.group_or_name} (#{@booking.date_range})",
      tag: "admin_booking_canceled"
    )
  end

  def space_booking_canceled(space_booking)
    @space_booking = SpaceBookingDecorator.new(space_booking)
    mail(
      to: "reservation@les4sources.be",
      subject: "⚠️ Réservation d'espaces annulée: #{@space_booking.group_or_name} (#{@space_booking.date_range})",
      tag: "admin_space_booking_canceled"
    )
  end
end