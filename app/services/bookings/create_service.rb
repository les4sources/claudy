module Bookings
  class CreateService < ServiceBase
    include Bookable
    include Subscribable

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
      @booking.attributes = booking_params(params)
      @booking.generate_token
      return false if !@booking.valid?
      set_invoice_status
      set_tier
      unset_lodging_id if @booking.booking_type == "rooms"
      rooms = get_rooms
      if !rooms.nil? && available?(rooms)
        build_reservations(rooms)
        @booking.save!
        notify_customer_on_create
        create_subscription(from: @booking)
      end
      raise error_message if !error.nil?
      true
    end
  end
end
