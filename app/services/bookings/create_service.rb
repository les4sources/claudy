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
      @booking.room_ids.compact_blank.each do |room_id|
        @booking.reservations.build(
          room_id: room_id,
          from_date: @booking.from_date,
          to_date: @booking.to_date
        )
      end
      @booking.save!
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
          :from_date,
          :to_date,
          :status,
          :adults,
          :children,
          :price,
          :payment_status,
          :payment_method,
          :bedsheets,
          :towels,
          :notes,
          room_ids: []
        )
    end
  end
end
