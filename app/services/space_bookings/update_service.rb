module SpaceBookings
  class UpdateService < ServiceBase
    include SpaceBookable

    attr_reader :space_booking

    def initialize(space_booking_id:)
      @report_errors = true
      @space_booking = SpaceBooking.find_by!(id: space_booking_id)
    end

    def run(params = {})
      context = {
        params: params,
        space_booking: space_booking&.attributes
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      @space_booking.attributes = space_booking_params(params)
      return false if !@space_booking.valid?
      # delete previous reservations as we will re-create them
      @space_booking.space_reservations.destroy_all
      spaces = get_spaces
      if !spaces.nil? && available?(spaces)
        build_space_reservations(spaces)
        @space_booking.save!
      end
      raise error_message if !error.nil?
      true
    end
  end
end
