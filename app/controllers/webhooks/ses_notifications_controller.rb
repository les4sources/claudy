require "net/http"

# Notifications Amazon SES (rebonds, plaintes), relayées par un sujet SNS
# abonné en HTTPS à cette adresse.
#
# Deux garde-fous avant de lire quoi que ce soit :
#   1. la signature SNS (`Aws::SNS::MessageVerifier`, certificat d'AWS) ;
#   2. le sujet : seul `AWS_SES_SNS_TOPIC_ARN` est accepté. Sans lui, n'importe
#      quel compte AWS pourrait abonner son propre sujet, signé lui aussi.
# Sans `AWS_SES_SNS_TOPIC_ARN`, tout est refusé.
class Webhooks::SesNotificationsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  SUBSCRIBE_HOST = /\Asns\.[a-z0-9-]+\.amazonaws\.com\z/

  def create
    payload = request.body.read
    sns = JSON.parse(payload)
    return head(:forbidden) unless expected_topic?(sns) && verifier.authentic?(payload)

    case sns["Type"]
    when "SubscriptionConfirmation" then confirm_subscription(sns["SubscribeURL"])
    when "Notification" then SentEmails::SesFeedback.new(JSON.parse(sns["Message"])).apply
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  rescue StandardError => e
    Sentry.capture_exception(e)
    head :unprocessable_content
  end

  private

  def expected_topic?(sns)
    topic = ENV["AWS_SES_SNS_TOPIC_ARN"]
    topic.present? && ActiveSupport::SecurityUtils.secure_compare(topic, sns["TopicArn"].to_s)
  end

  def verifier
    @verifier ||= Aws::SNS::MessageVerifier.new
  end

  # Le lien de confirmation ne peut mener qu'à SNS, en HTTPS.
  def confirm_subscription(url)
    uri = URI.parse(url.to_s)
    raise ArgumentError, "SubscribeURL inattendue : #{url}" unless uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(SUBSCRIBE_HOST)

    Net::HTTP.get_response(uri)
  end
end
