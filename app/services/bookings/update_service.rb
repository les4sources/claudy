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
      unset_lodging_id if @booking.booking_type == "rooms"
      set_tier
      ActiveRecord::Base.transaction do
        # delete previous reservations as we will re-create them
        @booking.reservations.destroy_all
        rooms = get_rooms
        if !rooms.nil? && available?(rooms)
          build_reservations(rooms)
          @booking.save!
          @booking.set_payment_status
          # Stay-first (epic #26, Phase 3) : soigne un Booking legacy dépourvu de Stay
          # (créé avant le backfill ou via un bypass). Idempotent — no-op si un Stay
          # vivant existe déjà. Dans la transaction pour rester atomique avec le save.
          Stays::EnsureForBooking.call(@booking)
        end
      end
      raise error_message if !error.nil?
      true
    end
  end
end
