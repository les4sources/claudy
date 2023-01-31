module Bookings
  class CreateService < ServiceBase
    attr_reader :booking, :reservation

    def initialize
      @booking = Booking.new
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      @booking.attributes = booking_params(params)
      byebug
      @booking.generate_token
      return false if !@booking.valid?
      case @booking.booking_type
      when "lodging"
        rooms = @booking.lodging.rooms
      when "rooms"
        rooms = Room.where(id: @booking.room_ids.compact_blank)
      else
        set_error_message(
          "Le type de réservation n'a pas pu être défini correctement."
        )
      end
      if check_availability(rooms)
        build_reservations(rooms)
        @booking.save!
      end
      raise error_message if !error.nil?
      true
    end

    private

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

    def check_availability(rooms)
      rooms.each do |room|
        if room.reservations.where(date: (@booking.from_date)..(@booking.to_date - 1.day)).any?
          set_error_message("Cet hébergement n'est pas disponible à cette date.")
          return false
        end
      end
    end
  end
end
