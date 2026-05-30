require "rails_helper"

RSpec.describe ReservationMailer, type: :mailer do
  let(:customer) { Customer.create!(email: "guest@example.com", first_name: "Léa") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  let(:booking) do
    b = Booking.new(firstname: "Léa", email: "guest@example.com",
                    from_date: Date.today + 30, to_date: Date.today + 32, adults: 2,
                    status: "pending", lodging_id: lodging.id, price_cents: 74_500, shown_price_cents: 74_500)
    b.generate_token
    b.save!
    b
  end

  let(:stay) do
    s = Stay.create!(customer: customer, source: "reservation", status: "pending",
                     arrival_date: Date.today + 30, departure_date: Date.today + 32,
                     total_amount_cents: 74_500)
    s.stay_items.create!(bookable: booking)
    s
  end

  describe "#confirmation_request (AC-T2-21 / AC-T2-17)" do
    subject(:mail) { described_class.confirmation_request(stay) }

    it "adresse le mail au Customer" do
      expect(mail.to).to eq(["guest@example.com"])
    end

    it "contient le lien token stable de consultation" do
      expect(mail.body.encoded).to include(booking.token)
    end

    it "affiche le breakdown TVAC issu du même PricingModel que l'UI" do
      expect(mail.body.encoded).to match(/Total TVAC/i)
      expect(mail.body.encoded).to include("745") # Hulotte 2 nuits = 485 + 260 = 745 €
      expect(mail.body.encoded).to match(/pas de TVA en plus/i)
    end
  end
end
