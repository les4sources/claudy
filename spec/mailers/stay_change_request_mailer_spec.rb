require "rails_helper"

# Issue #133 — emails de la demande de modification.
RSpec.describe StayChangeRequestMailer, type: :mailer do
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: Date.current + 10, departure_date: Date.current + 12,
                 total_amount_cents: 50_000)
  end

  def change(attrs = {})
    StayChangeRequest.create!({ stay: stay, draft_snapshot: {},
                                new_total_cents: 58_000, delta_cents: 8_000 }.merge(attrs))
  end

  it "prévient l'équipe avec le delta" do
    mail = described_class.team_new_request(change)

    expect(mail.to).to eq(["sejours@les4sources.be"])
    expect(mail.subject).to include("+80,00 €")
    expect(mail.text_part.decoded).to include("580,00 €")
  end

  it "accuse réception auprès du client" do
    mail = described_class.customer_received(change)

    expect(mail.to).to eq(["ana@example.com"])
    expect(mail.text_part.decoded).to include("bien reçu")
    expect(mail.text_part.decoded).to include("s'ajoutera à votre solde")
  end

  it "annonce la mention des 10 jours en cas de remboursement" do
    Payment.create!(stay: stay, amount_cents: 50_000, payment_method: "card", status: "paid")
    request = change(new_total_cents: 40_000, delta_cents: -10_000,
                     refund_iban: "BE68539007547034")

    expect(described_class.customer_received(request).text_part.decoded)
      .to include(StayChangeRequest::REFUND_NOTICE)
    expect(described_class.team_new_request(request).text_part.decoded)
      .to include("BE68539007547034")
  end

  it "annonce l'approbation avec nouveau total et solde" do
    mail = described_class.customer_approved(change(status: "approved"))

    expect(mail.subject).to include("modifié")
    expect(mail.text_part.decoded).to include("Nouveau total")
    expect(mail.text_part.decoded).to include("Solde restant")
    expect(mail.text_part.decoded).to include(stay.token)
  end

  it "annonce le refus avec son motif" do
    request = change(status: "refused", refusal_reason: "Le gîte est complet.")
    mail = described_class.customer_refused(request)

    expect(mail.text_part.decoded).to include("Le gîte est complet.")
    expect(mail.text_part.decoded).to include("reste inchangé")
  end
end
