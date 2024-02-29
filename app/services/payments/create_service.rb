module Payments
  class CreateService < ServiceBase
    attr_reader :booking
    attr_reader :payment

    def initialize(booking_id:)
      @booking = Booking.find(booking_id)
      @payment = @booking.payments.new
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
      @payment.attributes = payment_params(params)
      return false if !@payment.valid?
      @payment.save!
      @booking.set_payment_status
      raise error_message if !error.nil?
      true
    end

    private

    def payment_params(params)
      params
        .require(:payment)
        .permit(
          :amount,
          :payment_method
        )
    end
  end
end
