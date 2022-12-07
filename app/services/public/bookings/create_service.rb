module Public
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
        # TODO create reservations for lodging rooms
        @booking.room_ids.compact_blank.each do |room_id|
          (@booking.from_date..@booking.to_date).each do |date|
            @booking.reservations.build(
              room_id: room_id,
              date: date
            )
          end
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
            :estimated_arrival,
            :from_date,
            :to_date,
            :adults,
            :children,
            :payment_method,
            :invoice_wanted,
            :comments,
            :tier,
            :option_bread,
            :option_babysitting,
            :option_discgolf,
            :lodging_id
          )
      end
    end
  end
end
