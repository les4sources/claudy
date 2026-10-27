require "rails_helper"
require Rails.root.join("spec/support/env_helpers")

# Notifications Amazon SES relayées par SNS. La signature SNS est vérifiée par
# `Aws::SNS::MessageVerifier` (certificat téléchargé chez AWS) : bouchonnée ici.
RSpec.describe "Webhook Amazon SES", type: :request do
  let(:topic) { "arn:aws:sns:eu-west-1:123456789012:claudy-ses" }
  let!(:customer) do
    Customer.create!(email: "cliente@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end
  let!(:sent) do
    SentEmail.create!(customer: customer, to_email: customer.email, subject: "Séjour confirmé",
                      sent_at: 1.hour.ago, ses_message_id: "ses-1")
  end
  let(:bounce_message) do
    { "notificationType" => "Bounce",
      "bounce" => { "bounceType" => "Permanent", "bouncedRecipients" => [{ "emailAddress" => customer.email }] },
      "mail" => { "messageId" => "ses-1" } }
  end

  around { |example| with_env("AWS_SES_SNS_TOPIC_ARN" => topic) { example.run } }

  before do
    allow_any_instance_of(Aws::SNS::MessageVerifier).to receive(:authentic?).and_return(true)
  end

  def deliver(body)
    post "/webhooks/ses_notifications", params: body.to_json, headers: { "CONTENT_TYPE" => "text/plain" }
  end

  def notification(topic_arn: topic)
    { "Type" => "Notification", "TopicArn" => topic_arn, "Message" => bounce_message.to_json }
  end

  it "applique un rebond à l'email journalisé" do
    deliver(notification)

    expect(response).to have_http_status(:ok)
    expect(sent.reload.delivery_issue).to eq("bounce")
  end

  it "refuse une signature invalide" do
    allow_any_instance_of(Aws::SNS::MessageVerifier).to receive(:authentic?).and_return(false)
    deliver(notification)

    expect(response).to have_http_status(:forbidden)
    expect(sent.reload.delivery_issue).to be_nil
  end

  it "refuse un autre sujet SNS, même signé" do
    deliver(notification(topic_arn: "arn:aws:sns:eu-west-1:999999999999:intrus"))

    expect(response).to have_http_status(:forbidden)
    expect(sent.reload.delivery_issue).to be_nil
  end

  it "refuse tout tant que le sujet n'est pas configuré" do
    with_env("AWS_SES_SNS_TOPIC_ARN" => nil) { deliver(notification) }
    expect(response).to have_http_status(:forbidden)
  end

  it "confirme l'abonnement en suivant le lien SNS" do
    url = "https://sns.eu-west-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc"
    expect(Net::HTTP).to receive(:get_response).with(URI.parse(url))

    deliver("Type" => "SubscriptionConfirmation", "TopicArn" => topic, "SubscribeURL" => url)
    expect(response).to have_http_status(:ok)
  end

  it "ne suit jamais un lien de confirmation hors de SNS" do
    expect(Net::HTTP).not_to receive(:get_response)

    deliver("Type" => "SubscriptionConfirmation", "TopicArn" => topic,
            "SubscribeURL" => "https://example.com/piege")
    expect(response).to have_http_status(:unprocessable_content)
  end
end
