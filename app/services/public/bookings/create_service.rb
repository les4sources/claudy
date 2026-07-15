module Public
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
        @booking.attributes = public_booking_params(params)
        @booking.generate_token
        return false if !@booking.valid?
        set_invoice_status
        set_tier
        rooms = get_rooms
        if ready_to_book?(rooms)
          initialize_public_booking
          set_price
          build_reservations(rooms)
          # Stay-first (epic #26, Phase 3) : le funnel public legacy (POST /public/bookings,
          # encore lié depuis le calendrier iframe et les mails) doit lui aussi produire un
          # Stay, sinon il recrée des Bookings sans Stay et casse l'invariant global. Booking
          # et Stay dans la MÊME transaction (échec du Stay ⇒ rollback du booking, zéro
          # orphelin) ; effets de bord (mails, abonnement) hors transaction.
          ActiveRecord::Base.transaction do
            @booking.save!
            Stays::EnsureForBooking.call(@booking)
          end
          notify_customer_on_create
          notify_admin_on_create
          create_subscription(from: @booking)
        end
        raise error_message if !error.nil?
        true
      end

      private

      def initialize_public_booking
        @booking.payment_status = "pending"
        @booking.platform = "web"
        @booking.status = "pending"
      end

      def ready_to_book?(rooms)
        case @booking.booking_type
        when "lodging"
          !rooms.nil? && available?(rooms) && any_people? && terms_approved?
        when "rooms"
          any_people? && terms_approved?
        end
      end

      def set_price
        @booking.price_cents = @booking.shown_price_cents
      end
    end
  end
end
