require "rails_helper"

# Michael 2026-10-19 — l'email « Paiement reçu » part à la compta (accueil en
# copie) et dit qui a payé quoi, sans devoir ouvrir Claudy.
RSpec.describe AdminMailer, type: :mailer do
  describe "#payment_received" do
    let(:customer) { Customer.create!(first_name: "Léa", last_name: "Dupont", email: "lea@example.com") }
    let(:stay) do
      Stay.create!(customer: customer, source: "reservation", status: "confirmed",
                   arrival_date: Date.new(2026, 11, 12), departure_date: Date.new(2026, 11, 14),
                   total_amount_cents: 80_000)
    end

    def pay(cents)
      Payment.create!(stay: stay, amount_cents: cents, status: "paid", payment_method: "card")
    end

    def body_of(mail)
      mail.body.decoded
    end

    it "écrit à la compta, avec l'accueil en copie" do
      mail = described_class.payment_received(pay(24_000))

      expect(mail.to).to eq(["compta@les4sources.be"])
      expect(mail.cc).to eq(["sejours@les4sources.be"])
      expect(mail.from).to eq(["sejours@les4sources.be"])
    end

    it "met le montant, le client et les dates dans l'objet" do
      mail = described_class.payment_received(pay(24_000))

      expect(mail.subject).to include("240,00")
      expect(mail.subject).to include("Dupont")
      expect(mail.subject).to include("12")
      expect(mail.subject).to include("novembre")
    end

    it "dit qu'un premier paiement partiel est un acompte, avec le reste à payer" do
      body = body_of(described_class.payment_received(pay(24_000)))

      expect(body).to include("Acompte")
      expect(body).to include("800,00")
      expect(body).to include("Reste à payer : 560,00")
      expect(body).to include("/stays/#{stay.id}")
    end

    it "dit qu'un paiement qui couvre le reste est le solde" do
      pay(24_000)
      body = body_of(described_class.payment_received(pay(56_000)))

      expect(body).to include("Solde")
      expect(body).to include("Reste à payer : 0,00")
    end

    it "reconnaît un paiement du montant total" do
      body = body_of(described_class.payment_received(pay(80_000)))

      expect(body).to include("Montant total du séjour")
    end

    it "fonctionne pour un pack de coworking, sans séjour" do
      pack = CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card",
                                   expires_at: Date.new(2027, 3, 1))
      payment = Payment.create!(coworking_pack: pack, amount_cents: 8_000, status: "paid",
                                payment_method: "card")
      mail = described_class.payment_received(payment)

      expect(mail.subject).to include("80,00")
      expect(mail.subject).to include("Dupont")
      expect(body_of(mail)).to include("Pack de coworking")
      expect(body_of(mail)).not_to include("Reste à payer")
    end
  end
end
