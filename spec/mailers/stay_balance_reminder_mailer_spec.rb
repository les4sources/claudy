require "rails_helper"

# Epic #55, Phase 5 — mailer de relance du solde exigible (client).
RSpec.describe StayBalanceReminderMailer, type: :mailer do
  let(:customer) do
    Customer.create!(email: "solde@example.com", first_name: "Léa", customer_type: "individual")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "pending", total_amount_cents: 15_000,
                 arrival_date: Date.today + 14, departure_date: Date.today + 16)
  end

  subject(:mail) { described_class.reminder(stay) }

  it "adresse la relance au client" do
    expect(mail.to).to eq(["solde@example.com"])
  end

  it "pointe vers la page séjour à jeton (paiement du solde)" do
    # Le lien de la relance porte le jeton public du séjour → /sejour/:token.
    expect(mail.body.encoded).to include(stay.token)
  end

  it "rassure explicitement : aucun blocage ni annulation" do
    expect(mail.body.encoded).to match(/rien n'est annulé|reste bien confirmée/)
  end
end
