module SpaceBookings
  class DuplicateService < ServiceBase
    include Bookable

    attr_reader :space_booking, :source_space_booking

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
      @source_space_booking = SpaceBooking.find(params[:source_space_booking_id])
      @space_booking = SpaceBooking.new(@source_space_booking.attributes)
      @space_booking.generate_token
      set_space_ids
      unset_attributes
      return false if !@space_booking.valid?
      raise error_message if !error.nil?
      true
    end

    private

    def set_space_ids
      @space_booking.space_ids = @source_space_booking.spaces.pluck(:id)
    end

    def unset_attributes
      @space_booking.status = nil
      @space_booking.from_date = nil
      @space_booking.to_date = nil
      @space_booking.arrival_time = nil
      @space_booking.departure_time = nil
      @space_booking.payment_status = nil
      @space_booking.invoice_status = nil
      @space_booking.contract_status = nil
    end
  end
end
