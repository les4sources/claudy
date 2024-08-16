module Payments
  class UpdateService < ServiceBase
    attr_reader :reservation
    attr_reader :payment

    def initialize(payment_id:)
      @payment = Payment.find(payment_id)
      @reservation = @payment.booking.nil? ? @payment.stay : @payment.booking
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
      ActiveRecord::Base.transaction do
        @payment.save!
        @reservation.set_payment_status
      end
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
