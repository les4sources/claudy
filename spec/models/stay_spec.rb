require "rails_helper"

RSpec.describe Stay, type: :model do
  let(:customer) { Customer.create!(email: "stay@example.com", customer_type: "individual") }

  def booking(from:, to:, price_cents: 0, status: "confirmed")
    Booking.create!(firstname: "Stay", from_date: from, to_date: to, adults: 1,
                    status: status, price_cents: price_cents)
  end

  describe "associations" do
    it "belongs to a customer and has many stay items" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      stay.stay_items.create!(bookable: b)
      expect(stay.customer).to eq(customer)
      expect(stay.bookables).to contain_exactly(b)
    end
  end

  describe "#payments (read-derived, §11.6)" do
    it "returns the payments of its Booking items" do
      stay = Stay.create!(customer: customer)
      b = booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3))
      stay.stay_items.create!(bookable: b)
      payment = Payment.create!(booking: b, amount_cents: 5_000, status: "paid", payment_method: "card")

      expect(stay.payments).to contain_exactly(payment)
    end

    it "returns no payments for a stay made only of space bookings" do
      stay = Stay.create!(customer: customer)
      sb = SpaceBooking.create!(firstname: "Salle", from_date: Date.new(2026, 7, 1),
                                to_date: Date.new(2026, 7, 1), status: "confirmed")
      stay.stay_items.create!(bookable: sb)

      expect(stay.payments).to be_empty
    end
  end

  describe "#recompute_aggregates!" do
    it "derives min arrival, max departure and summed amount from its items" do
      stay = Stay.create!(customer: customer)
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 5), to: Date.new(2026, 7, 8), price_cents: 30_000))
      stay.stay_items.create!(bookable: booking(from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 3), price_cents: 20_000))

      stay.recompute_aggregates!

      expect(stay.arrival_date).to eq(Date.new(2026, 7, 1))
      expect(stay.departure_date).to eq(Date.new(2026, 7, 8))
      expect(stay.total_amount_cents).to eq(50_000)
    end
  end

  describe "scopes" do
    it "separates current/future stays from past ones" do
      future = Stay.create!(customer: customer, arrival_date: Date.today + 5, departure_date: Date.today + 10)
      past = Stay.create!(customer: customer, arrival_date: Date.today - 10, departure_date: Date.today - 5)

      expect(Stay.current_and_future).to include(future)
      expect(Stay.current_and_future).not_to include(past)
      expect(Stay.past).to include(past)
      expect(Stay.past).not_to include(future)
    end
  end

  describe "#source (Q9 — AC-T2-22 / AC-T2-22b)" do
    it "défaute sur 'reservation' quand non précisé" do
      stay = Stay.create!(customer: customer)
      expect(stay.source).to eq("reservation")
    end

    it "est distinct de legacy_origin (clé d'import/dédup)" do
      stay = Stay.create!(customer: customer, source: "reservation", legacy_origin: "booking:42")
      expect(stay.source).to eq("reservation")
      expect(stay.legacy_origin).to eq("booking:42")
    end

    it "refuse une valeur de canal inconnue" do
      stay = Stay.new(customer: customer, source: "carrier-pigeon")
      expect(stay).not_to be_valid
      expect(stay.errors[:source]).to be_present
    end

    it "filtre par canal via le scope from_source" do
      reservation = Stay.create!(customer: customer, source: "reservation")
      tally = Stay.create!(customer: customer, source: "tally_legacy")
      expect(Stay.from_source("reservation")).to include(reservation)
      expect(Stay.from_source("reservation")).not_to include(tally)
      expect(Stay.from_source(nil)).to include(reservation, tally)
    end
  end
end
