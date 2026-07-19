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
      spaces = get_spaces
      if !spaces.nil? && available?(spaces)
        build_space_reservations(spaces, @space_booking.duration)
        # Stay-first (epic #81, Phase 1) : tout SpaceBooking créé côté admin obtient
        # automatiquement un Stay + Customer, comme le canal Booking. SpaceBooking et
        # Stay sont persistés dans la MÊME transaction — un échec de Stay annule le
        # space_booking pour ne jamais laisser d'orphelin. Les effets de bord (email,
        # abonnement) restent hors transaction.
        ActiveRecord::Base.transaction do
          @space_booking.save!
          Stays::EnsureForSpaceBooking.call(@space_booking)
        end
        notify_customer_on_create
        create_subscription(from: @space_booking)
      end
      raise error_message if !error.nil?
      true
    end
  end
end
