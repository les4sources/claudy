module Payments
  class DestroyService < ServiceBase
    attr_reader :booking
    attr_reader :payment

    def initialize(payment_id:)
      @payment = Payment.find(payment_id)
      @booking = @payment.booking
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
      @payment.soft_delete!(validate: false)
      @booking.set_payment_status
      raise error_message if !error.nil?
      true
    end
  end
end
