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
        @booking.generate_token
        return false if !@booking.valid?
        rooms = get_rooms
        if !rooms.nil? && available?(rooms) && any_people?
          set_payment_status
          set_price
          set_status
          set_platform
          build_reservations(rooms)
          @booking.save!
        end
        raise error_message if !error.nil?
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
            :booking_type,
            :from_date,
            :to_date,
            :adults,
            :children,
            :estimated_arrival,
            :shown_price_cents,
            :payment_method,
            :invoice_wanted,
            :comments,
            :tier,
            :option_partyhall,
            :option_bread,
            :option_babysitting,
            :option_discgolf,
            :lodging_id,
            room_ids: []
          )
      end

      def available?(rooms)
        rooms.each do |room|
          if room.reservations.where(date: (@booking.from_date)..(@booking.to_date)).any?
            set_error_message("Cet hébergement n'est pas disponible à cette date. Pourriez-vous vérifier sur le calendrier?")
            return false
          end
        end
      end

      def build_reservations(rooms)
        rooms.each do |room|
          (@booking.from_date..(@booking.to_date - 1.day)).each do |date|
            @booking.reservations.build(
              room: room,
              date: date
            )
          end
        end
      end

      def get_rooms
        case @booking.booking_type
        when "lodging"
          if @booking.lodging.nil?
            set_error_message("Veuillez sélectionner un hébergement")
            nil
          else
            @booking.lodging.rooms
          end
        when "rooms"
          Room.where(id: @booking.room_ids.compact_blank)
        else
          set_error_message(
            "Le type de réservation n'a pas pu être défini correctement."
          )
          nil
        end
      end

      def set_payment_status
        @booking.payment_status = "unpaid"
      end

      def set_platform
        @booking.platform = "web"
      end

      def set_price
        # TODO call a service
        @booking.price = 999
      end

      def set_status
        @booking.status = "pending"
      end
    end
  end
end
