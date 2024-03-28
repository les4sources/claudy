module Paylinks
  class CreateService < ServiceBase
    attr_reader :booking
    attr_reader :paylink

    def initialize(booking_id:)
      @booking = Booking.find(booking_id)
      @paylink = @booking.paylinks.new
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
      @paylink.attributes = paylink_params(params)
      return false if !@paylink.valid?
      @paylink.checkout_url = stripe_checkout.url
      @paylink.save!
      raise error_message if !error.nil?
      true
    end

    private

    def stripe_checkout
      StripeService.instance.create_stripe_checkout_session(
        email: @booking.email,
        success_url: public_paylink_url(@paylink),
        cancel_url: public_booking_url(@booking),
        item: {
          id: @booking.id,
          name: "Réservation ##{@booking.token}",
          amount: @paylink.amount
        }
      )
    end

    def paylink_params(params)
      params
        .require(:paylink)
        .permit(
          :amount
        )
    end
  end
end
