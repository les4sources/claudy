module Webhooks
  class StripeService < ServiceBase
    require "json"

    attr_reader :event

    def initialize(event:)
      @event = event
    end

    def run!
      # Do not save or act upon a duplicate event
      unless StripeEvent.where(webhook_id: event.id).present?
        case event.type
        when "checkout.session.completed" then checkout_session_completed(event)
        # Async payment methods have a webhook that is only slightly different for session completion
        when "checkout.session.async_payment_succeeded" then checkout_session_completed(event)
        end
      end
    end

    private

    # https://stripe.com/docs/payments/checkout/fulfillment#webhooks
    def checkout_session_completed(event)
      save_event_to_db(event)
      payment = Payment.where(id: event.data.object[:client_reference_id]).take
      if payment&.pending?
        Stripe::CompletedCheckoutService.new(payment: payment).run!(
          stripe_checkout_session_id: event.data.object.id,
          stripe_payment_intent_id: event.data.object.payment_intent
        )
      end
    rescue ActiveModel::RangeError
      # Do nothing... would have failed anyway
    end

    def save_event_to_db(event)
      StripeEvent.create(
        webhook_id: event.id,
        event_type: event.type,
        object_id:  event.data.object.id
      )
    end
  end
end
