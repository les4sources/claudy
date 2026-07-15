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
        success_url: return_url,
        cancel_url: return_url,
        item: {
          id: @payment.id,
          name: checkout_label,
          amount: @payment.amount_cents
        }
      )
    end

    # Stay-first (epic #26, Phase 2) : le client revient sur la page séjour dès
    # que le paiement est rattaché à un Stay. Repli sur la page booking pour les
    # paiements historiques, dont les liens circulent encore par email.
    def return_url
      if @payment.stay&.token.present?
        public_stay_url(@payment.stay.token)
      else
        public_booking_url(@payment.booking.token)
      end
    end

    def checkout_label
      if @payment.stay&.token.present?
        "Séjour ##{@payment.stay.token}"
      else
        "Réservation ##{@payment.booking.token}"
      end
    end
  end
end
