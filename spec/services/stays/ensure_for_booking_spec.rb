require "rails_helper"

RSpec.describe Stays::EnsureForBooking do
  def build_booking(**attrs)
    Booking.create!({
      firstname: "Zoé",
      lastname: "Durand",
      email: "zoe@example.com",
      from_date: Date.new(2026, 8, 1),
      to_date: Date.new(2026, 8, 4),
      adults: 2,
      status: "pending",
      price_cents: 30_000
    }.merge(attrs))
  end

  describe "création d'un Stay pour un Booking qui n'en a pas" do
    it "crée le Stay, le StayItem et upserte le Customer par email" do
      booking = build_booking

      stay = described_class.call(booking)

      expect(stay).to be_persisted
      expect(booking.reload.stay).to eq(stay)
      expect(stay.customer.email).to eq("zoe@example.com")
      expect(stay.stay_items.map(&:bookable)).to contain_exactly(booking)
    end

    it "recopie dates, statut et montant depuis le booking sans le muter" do
      booking = build_booking

      expect { described_class.call(booking) }.not_to change { booking.reload.attributes }

      stay = booking.reload.stay
      expect(stay.arrival_date).to eq(Date.new(2026, 8, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 8, 4))
      expect(stay.status).to eq("pending")
      expect(stay.total_amount_cents).to eq(30_000)
    end

    it "attribue source 'ota' pour une résa airbnb" do
      stay = described_class.call(build_booking(platform: "airbnb"))
      expect(stay.source).to eq("ota")
    end

    it "attribue source 'ota' pour une résa bookingdotcom" do
      stay = described_class.call(build_booking(platform: "bookingdotcom"))
      expect(stay.source).to eq("ota")
    end

    it "attribue source 'manual' pour une saisie admin classique" do
      stay = described_class.call(build_booking(platform: "web"))
      expect(stay.source).to eq("manual")
    end

    it "rattache un booking sans email exploitable au Customer fourre-tout" do
      stay = described_class.call(build_booking(email: nil))
      expect(stay.customer.catch_all?).to be(true)
    end

    it "crée un Customer organisation quand group_name est présent" do
      stay = described_class.call(build_booking(email: "asso@example.com", group_name: "Les Amis"))
      expect(stay.customer.customer_type).to eq("organization")
      expect(stay.customer.organization_name).to eq("Les Amis")
    end
  end

  describe "idempotence" do
    it "renvoie le Stay existant sans en créer un second" do
      booking = build_booking
      first = described_class.call(booking)

      second = nil
      expect { second = described_class.call(booking) }.not_to change(Stay, :count)
      expect(second).to eq(first)
      expect(StayItem.where(bookable: booking).count).to eq(1)
    end
  end
end
