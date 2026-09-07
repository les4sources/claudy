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

  # Issue #232 — un client peut vivre sans email : la relance se tait plutôt que
  # de lever faute de destinataire.
  context "quand le client n'a pas d'adresse email" do
    let(:customer) { Customer.create!(email: nil, first_name: "Jean", last_name: "Sanmail") }

    it "n'envoie rien et ne lève pas" do
      ActionMailer::Base.deliveries.clear

      expect { mail.deliver_now }.not_to raise_error
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
