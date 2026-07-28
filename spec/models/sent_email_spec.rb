require "rails_helper"

# Journal des emails envoyés à un client (fiche client → « Emails envoyés »).
RSpec.describe SentEmail, type: :model do
  let(:customer) do
    Customer.create!(email: "journal@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end

  def build_email(attrs = {})
    described_class.new({ customer: customer, to_email: customer.email,
                          subject: "Bonjour", sent_at: Time.current }.merge(attrs))
  end

  it "exige un client, un destinataire et une date d'envoi" do
    expect(build_email).to be_valid
    expect(build_email(customer: nil)).not_to be_valid
    expect(build_email(to_email: nil)).not_to be_valid
    expect(build_email(sent_at: nil)).not_to be_valid
  end

  it "n'accepte que les sources connues" do
    expect(build_email(source: "app")).to be_valid
    expect(build_email(source: "postmark")).to be_valid
    expect(build_email(source: "carrier-pigeon")).not_to be_valid
  end

  it "classe du plus récent au plus ancien" do
    old    = described_class.create!(customer: customer, to_email: customer.email, subject: "Ancien", sent_at: 3.days.ago)
    recent = described_class.create!(customer: customer, to_email: customer.email, subject: "Récent", sent_at: 1.hour.ago)

    expect(described_class.recent.to_a).to eq([recent, old])
  end

  it "affiche un sujet de repli quand l'email n'en portait pas" do
    expect(build_email(subject: nil).display_subject).to eq("(sans sujet)")
  end

  # Le MessageID Postmark est la clé de dédoublonnage entre journal local et
  # backfill : deux lignes ne peuvent pas le partager.
  it "refuse deux lignes portant le même MessageID Postmark" do
    described_class.create!(customer: customer, to_email: customer.email, sent_at: Time.current,
                            postmark_message_id: "pm-1")

    expect {
      described_class.create!(customer: customer, to_email: customer.email, sent_at: Time.current,
                              postmark_message_id: "pm-1")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "tolère plusieurs lignes sans MessageID (dev, tests, envois hors Postmark)" do
    2.times { described_class.create!(customer: customer, to_email: customer.email, sent_at: Time.current) }

    expect(customer.sent_emails.count).to eq(2)
  end
end
