module Bookings
  class UpdateService < ServiceBase
    include Bookable

    attr_reader :booking

    def initialize(booking_id:)
      @report_errors = true
      @booking = Booking.find_by!(id: booking_id)
    end

    def run(params = {})
      context = {
        params: params,
        booking: booking&.attributes
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      @booking.attributes = booking_params(params)
      return false if !@booking.valid?
      ActiveRecord::Base.transaction do
        # delete previous reservations as we will re-create them
        Reservation.soft_delete_all!(@booking.reservations)
        rooms = get_rooms
        if !rooms.nil? && available?(rooms)
          build_reservations(rooms)
          @booking.save!
        end
      end
      raise error_message if !error.nil?
      true
    end
  end
end
