module Bookable
  extend ActiveSupport::Concern

  private

  def any_people?
    @booking.adults > 0
  end

  def available?(rooms)
    rooms.each do |room|
      if room.reservations.where(date: (@booking.from_date)..(@booking.to_date - 1.day)).any?
        set_error_message("Cet hébergement n'est pas disponible à cette date.")
        return false
      end
    end
  end

  def build_reservations(rooms)
    rooms.each do |room|
      (@booking.from_date..(@booking.to_date - 1.day)).each do |date|
        @booking.reservations.build(
          room: room,
          date: date
        )
      end
    end
  end

  def get_rooms
    case @booking.booking_type
    when "lodging"
      @booking.lodging.rooms
    when "rooms"
      Room.where(id: @booking.room_ids&.compact_blank)
    else
      set_error_message(
        "Le type de réservation n'a pas pu être défini correctement."
      )
      nil
    end
  end

  def booking_params(params)
    params
      .require(:booking)
      .permit(
        :adults,
        :bedsheets,
        :booking_type,
        :children,
        :email,
        :estimated_arrival,
        :firstname,
        :from_date,
        :group_name,
        :invoice_wanted,
        :lastname,
        :lodging_id,
        :notes,
        :option_babysitting,
        :option_bread,
        :option_discgolf,
        :option_partyhall,
        :payment_method,
        :payment_status,
        :platform,
        :phone,
        :price,
        :shown_price_cents,
        :status,
        :tier,
        :to_date,
        :towels,
        room_ids: [],
      )
  end

  def public_booking_params(params)
    params
      .require(:booking)
      .permit(
        :adults,
        :booking_type,
        :children,
        :comments,
        :estimated_arrival,
        :email,
        :firstname,
        :from_date,
        :invoice_wanted,
        :lastname,
        :lodging_id,
        :option_babysitting,
        :option_bread,
        :option_discgolf,
        :option_partyhall,
        :payment_method,
        :phone,
        :shown_price_cents,
        :tier,
        :to_date,
        room_ids: []
      )
  end
end
