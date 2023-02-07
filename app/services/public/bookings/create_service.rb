module Public
  module Bookings
    class CreateService < ServiceBase
      include Bookable

      attr_reader :booking

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
        @booking.attributes = public_booking_params(params)
        @booking.generate_token
        return false if !@booking.valid?
        rooms = get_rooms
        if ready_to_book?(rooms) 
          initialize_public_booking
          set_price
          build_reservations(rooms)
          @booking.save!
        end
        raise error_message if !error.nil?
        true
      end

      private

      def initialize_public_booking
        @booking.payment_status = "pending"
        @booking.platform = "web"
        @booking.status = "pending"
      end

      def ready_to_book?(rooms)
        case @booking.booking_type
        when "lodging"
          !rooms.nil? && available?(rooms) && any_people?
        when "rooms"
          any_people?
        end
      end

      def set_price
        # TODO call a service that calculates prices
        @booking.price_cents = @booking.shown_price_cents
      end
    end
  end
end
