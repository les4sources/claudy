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
        return false if !@booking.valid?
        puts @booking.inspect
        case @booking.booking_type
        when "lodging"
          set_lodging
          check_lodging_availability # error should stop the process
          set_price
          if @booking.valid?
            book_lodging
          else
            return false
          end
        when "rooms"
          check_rooms_availability
          set_price
          if @booking.valid?
            book_rooms
          else
            return false
          end
        else
          @booking.errors.add(
            :base,
            "Le type de réservation n'a pas pu être défini correctement.
            Veuillez ré-essayer ou nous contacter par email: reservation@les4sources.be."
          )
        end
        # TODO create reservations for lodging rooms
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

      def book_lodging
        @booking.lodging.rooms.each do |room|
          (@booking.from_date..@booking.to_date).each do |date|
            @booking.reservations.build(
              room: room,
              date: date
            )
          end
        end
      end

      def book_rooms
        @booking.room_ids.compact_blank.each do |room_id|
          (@booking.from_date..@booking.to_date).each do |date|
            @booking.reservations.build(
              room_id: room_id,
              date: date
            )
          end
        end
      end

      def check_lodging_availability
        # TODO check availability
        set_error_message("Cet hébergement n'est pas disponible à cette date. Pourriez-vous vérifier sur le calendrier?")
        # @booking.errors.add(:base, )
      end

      def check_rooms_availability
        # TODO check availability
        set_error_message("Cet hébergement n'est pas disponible à cette date. Pourriez-vous vérifier sur le calendrier?")
        # @booking.errors.add(:base, "Cet hébergement n'est pas disponible à cette date. Pourriez-vous vérifier sur le calendrier?")
      end

      def set_lodging
        @booking.lodging = Lodging.find(@booking.lodging_id)
      end

      def set_price
        # TODO call a service
        @booking.price = 999
      end
    end
  end
end
