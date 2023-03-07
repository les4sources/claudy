module SpaceBookings
  class CreateService < ServiceBase
    include SpaceBookable
    include Subscribable

    attr_reader :space_booking

    def initialize
      @space_booking = SpaceBooking.new
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
      @space_booking.attributes = space_booking_params(params)
      @space_booking.generate_token
      return false if !@space_booking.valid?
      set_invoice_status
      spaces = get_spaces
      if !spaces.nil? && available?(spaces)
        build_space_reservations(spaces)
        @space_booking.save!
        notify_customer_on_create
        create_subscription(from: @space_booking)
      end
      raise error_message if !error.nil?
      true
    end
  end
end
