class Webhooks::StripeHooksController < ApplicationController
  require "json"

  skip_before_action :verify_authenticity_token, raise: false

  def create
    begin
      payload = request.body.read
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      endpoint_secret = ENV['STRIPE_WEBHOOK_ENDPOINT_SECRET']
      event = nil

      begin
        event = Stripe::Webhook.construct_event(
          payload, sig_header, endpoint_secret
        )
      # Invalid payload
      rescue JSON::ParserError
        render json: { error: "ParserError" }, status: 400
        return
      # Invalid signature
      rescue Stripe::SignatureVerificationError
        render json: { error: "SignatureVerificationError" }, status: 400
        return
      end

      # All good, let's evalute the webhook and create any necessary jobs
      Webhooks::StripeService.new(event: event).run!
      render json: {}, status: 200
    rescue StandardError => error
      Sentry.capture_exception(error)
      render json: { error: "Webhook call failed" }, status: 422
      return
    end
  end
end
