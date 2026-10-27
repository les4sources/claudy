require "rails_helper"

# Rebonds et plaintes signalés par Amazon SES, appliqués au journal des emails.
RSpec.describe SentEmails::SesFeedback do
  let!(:customer) do
    Customer.create!(email: "cliente@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end
  let!(:sent) do
    SentEmail.create!(customer: customer, to_email: customer.email, subject: "Séjour confirmé",
                      sent_at: 1.hour.ago, ses_message_id: "ses-1")
  end

  def bounce(type: "Permanent", sub_type: "General", address: "Cliente@Example.com", message_id: "ses-1")
    {
      "notificationType" => "Bounce",
      "bounce" => {
        "bounceType" => type, "bounceSubType" => sub_type, "timestamp" => "2026-10-27T08:00:00.000Z",
        "bouncedRecipients" => [{ "emailAddress" => address, "diagnosticCode" => "smtp; 550 5.1.1 user unknown" }]
      },
      "mail" => { "messageId" => message_id }
    }
  end

  it "marque l'email en rebond définitif, avec la raison et l'heure" do
    expect(described_class.new(bounce).apply).to eq(1)

    sent.reload
    expect(sent.delivery_issue).to eq("bounce")
    expect(sent.delivery_issue_detail).to eq("smtp; 550 5.1.1 user unknown")
    expect(sent.delivery_issue_at).to eq(Time.zone.parse("2026-10-27T08:00:00Z"))
  end

  it "distingue un refus temporaire" do
    described_class.new(bounce(type: "Transient", sub_type: "MailboxFull")).apply
    expect(sent.reload.delivery_issue).to eq("soft_bounce")
  end

  it "marque une plainte (spam)" do
    described_class.new(
      "notificationType" => "Complaint",
      "complaint" => { "complainedRecipients" => [{ "emailAddress" => customer.email }],
                       "complaintFeedbackType" => "abuse", "timestamp" => "2026-10-27T09:00:00Z" },
      "mail" => { "messageId" => "ses-1" }
    ).apply

    sent.reload
    expect(sent.delivery_issue).to eq("complaint")
    expect(sent.delivery_issue_detail).to eq("abuse")
  end

  it "accepte le format des configuration sets (eventType)" do
    notification = bounce.except("notificationType").merge("eventType" => "Bounce")
    expect(described_class.new(notification).apply).to eq(1)
  end

  it "ne touche à rien pour un autre message ou une remise réussie" do
    expect(described_class.new(bounce(message_id: "ses-autre")).apply).to eq(0)
    expect(described_class.new("notificationType" => "Delivery", "mail" => { "messageId" => "ses-1" }).apply).to eq(0)
    expect(sent.reload.delivery_issue).to be_nil
  end
end
