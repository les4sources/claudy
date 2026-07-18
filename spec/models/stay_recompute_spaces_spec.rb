require "rails_helper"

# Epic #66, Phase 2 — `Stay#recompute_aggregates!` doit tolérer un séjour SANS
# hébergement : dates + total dérivés des SpaceBooking, et surtout ne JAMAIS
# écraser les dates à nil quand aucun bookable daté n'est présent.
RSpec.describe Stay, "#recompute_aggregates! (espaces seuls, epic #66)" do
  let!(:customer) { Customer.create!(email: "c@example.com", first_name: "C", customer_type: "individual") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def stay_with_space
    stay = Stay.create!(customer: customer, source: "manual", status: "pending",
                        arrival_date: arrival, departure_date: departure, total_amount_cents: 0)
    space = Space.create!(name: "Grande Salle", capacity: 1)
    sb = SpaceBooking.create!(firstname: "C", from_date: arrival, to_date: departure,
                              status: "pending", price_cents: 29_000)
    sb.space_reservations.create!(space: space, date: arrival, duration: "journee")
    stay.stay_items.create!(bookable: sb)
    stay
  end

  it "dérive dates et total depuis le SpaceBooking (sans Booking)" do
    stay = stay_with_space
    stay.recompute_aggregates!
    stay.reload

    expect(stay.total_amount_cents).to eq(29_000)
    expect(stay.arrival_date).to eq(arrival)
    expect(stay.departure_date).to eq(departure)
  end

  it "n'écrase pas les dates à nil quand aucun bookable daté n'existe" do
    stay = Stay.create!(customer: customer, source: "manual", status: "pending",
                        arrival_date: arrival, departure_date: departure, total_amount_cents: 5_000)
    stay.recompute_aggregates!
    stay.reload

    expect(stay.arrival_date).to eq(arrival)
    expect(stay.departure_date).to eq(departure)
    expect(stay.total_amount_cents).to eq(0) # aucun bookable ni activité
  end
end
