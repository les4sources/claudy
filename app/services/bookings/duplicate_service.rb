module Bookings
  class DuplicateService < ServiceBase
    include Bookable

    attr_reader :booking, :source_booking

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
      @source_booking = Booking.find(params[:source_booking_id])
      @booking = Booking.new(@source_booking.attributes)
      @booking.generate_token
      set_booking_type
      set_room_ids
      set_tier_radio
      unset_attributes
      return false if !@booking.valid?
      raise error_message if !error.nil?
      true
    end

    private

    def set_room_ids
      @booking.room_ids = @source_booking.rooms.pluck(:id)
    end

    def set_booking_type
      if @booking.lodging_id.nil?
        @booking.booking_type = "rooms"
      else
        @booking.booking_type = "lodging"
      end
    end

    def set_tier_radio
      if @booking.booking_type == "lodging"
        @booking.tier_lodgings = @source_booking.tier
      else
        @booking.tier_rooms = @source_booking.tier
      end
    end

    def unset_attributes
      @booking.status = nil
      @booking.from_date = nil
      @booking.to_date = nil
      @booking.estimated_arrival = nil
      @booking.departure_time = nil
      @booking.payment_status = nil
      @booking.invoice_status = nil
      @booking.contract_status = nil
    end
  end
end
