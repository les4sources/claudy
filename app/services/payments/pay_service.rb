module Payments
  class PayService < ServiceBase
    include Routing

    attr_reader :payment
    attr_reader :checkout_session_url

    def initialize(payment_id:)
      @payment = Payment.find(payment_id)
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
      raise "Ce paiement a déjà été effectué" if @payment.paid?
      @checkout_session_url = stripe_checkout.url
      true
    end

    private

    def stripe_checkout
      StripeService.instance.create_checkout_session(
        client_reference_id: @payment.id,
        success_url: public_stay_url(@payment.stay.token),
        cancel_url: public_stay_url(@payment.stay.token),
        item: {
          id: @payment.id,
          name: "Séjour ##{@payment.stay.token}",
          amount: @payment.amount_cents
        }
      )
    end
  end
end
