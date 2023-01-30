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
          :firstname,
          :lastname,
          :phone,
          :email,
          :booking_type,
          :estimated_arrival,
          :from_date,
          :to_date,
          :status,
          :adults,
          :children,
          :price,
          :payment_status,
          :payment_method,
          :invoice_wanted,
          :bedsheets,
          :towels,
          :notes,
          :tier,
          :option_partyhall,
          :option_bread,
          :option_babysitting,
          :option_discgolf,
          :lodging_id,
          room_ids: [],
        )
    end

    def build_reservations(rooms)
      rooms.each do |room|
        (@booking.from_date..@booking.to_date).each do |date|
          @booking.reservations.build(
            room: room,
            date: date
          )
        end
      end
    end

    def check_availability(rooms)
      rooms.each do |room|
        if room.reservations.where(date: (@booking.from_date)..(@booking.to_date)).any?
          set_error_message("Cet hébergement n'est pas disponible à cette date.")
          return false
        end
      end
    end
  end
end
