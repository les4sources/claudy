require "rails_helper"

# Epic #126, Phase 3 — emails du coworking. Sobres : un fait par email.
RSpec.describe CoworkingMailer, type: :mailer do
  let(:customer) { Customer.create!(first_name: "Ana", email: "ana@example.com") }
  let(:pack) do
    CoworkingPack.create!(customer: customer, days_total: 5, payment_method: "card",
                          expires_at: Date.new(2027, 3, 1))
  end

  describe "#pack_purchased" do
    subject(:mail) { described_class.pack_purchased(pack) }

    it "adresse au client avec montant, journées et expiration" do
      expect(mail.to).to eq(["ana@example.com"])
      expect(mail.subject).to include("pack de coworking")
      body = mail.body.encoded
      expect(body).to include("5")            # journées
      expect(body).to include("80")           # 80 €
      expect(body).to include("mars 2027")    # expiration
    end
  end

  describe "#reservation_confirmed" do
    it "confirme la date réservée" do
      res = pack.coworking_reservations.create!(date: next_weekday, customer: customer)
      mail = described_class.reservation_confirmed(res)
      expect(mail.to).to eq(["ana@example.com"])
      expect(mail.subject).to include("réservée")
      expect(mail.body.encoded).to include(res.date.day.to_s)
    end
  end

  describe "#reservation_cancelled" do
    it "confirme l'annulation" do
      res = pack.coworking_reservations.create!(date: next_weekday, customer: customer)
      mail = described_class.reservation_cancelled(res)
      expect(mail.subject).to include("annulée")
      expect(mail.body.encoded).to include("annul")
    end
  end

  def next_weekday
    d = Date.current + 14
    d += 1 until (1..5).cover?(d.wday)
    d
  end
end
