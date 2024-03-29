module Stripe
  class CompletedCheckoutService < ServiceBase
    attr_reader :payment

    def initialize(payment:)
      @payment = payment
    end

    def run!(params = {})
      payment.update(
        status: "paid",
        stripe_checkout_session_id: params[:stripe_checkout_session_id],
        stripe_payment_intent_id: params[:stripe_payment_intent_id]
      )
      @payment.booking.set_payment_status
      email_admin
      true
    end

    private

    def email_admin
      AdminMailer.payment_received(payment).deliver_later
    end
  end
end
