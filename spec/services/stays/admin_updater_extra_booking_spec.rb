require "rails_helper"

# Séjour #1438 (Malau, 2026-10-27) : un second Booking, sans gîte et resté en
# avril, n'était jamais touché à l'édition. Le séjour passé en janvier gardait
# donc sa date de fin en avril, quoi qu'on saisisse au formulaire.
RSpec.describe Stays::AdminUpdater, "Booking en trop laissé par l'historique" do
  let!(:grand_duc) do
    lodging = Lodging.create!(name: "Le Grand-Duc", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival) { Date.today + 60 }
  let(:late_from) { arrival + 98 }

  def draft(departure:)
    Reservations::Draft.new(
      lodging_id: grand_duc.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      adults: 20, children: 10, dogs_count: 0,
      first_name: "Céline", last_name: "Martin",
      email: "celine-1438@example.com", phone: "+32470112233"
    )
  end

  let(:stay) do
    builder = Reservations::Builder.new(
      draft: draft(departure: arrival + 2), admin: true, status: "confirmed", source: "manual"
    )
    builder.run!
    builder.stay
  end

  let!(:extra) do
    booking = Booking.create!(firstname: "Céline", from_date: late_from, to_date: late_from + 2,
                              adults: 20, children: 10, status: "confirmed", price_cents: 0)
    stay.stay_items.create!(bookable: booking)
    stay.recompute_aggregates!
    booking
  end

  it "part bien d'un séjour que le Booking en trop étire jusqu'en avril" do
    expect(stay.reload.departure_date).to eq(late_from + 2)
  end

  it "ramène la date de fin à celle du formulaire et retire le Booking en trop" do
    updater = described_class.new(stay: stay.reload, draft: draft(departure: arrival + 2), status: "confirmed")

    expect(updater.run).to be(true), updater.error_message
    stay.reload
    expect(stay.departure_date).to eq(arrival + 2)
    expect(stay.bookables.map(&:lodging)).to eq([grand_duc])
    expect(Booking.find_by(id: extra.id)).to be_nil
  end

  it "rouvre le formulaire sur le Booking qui porte le gîte" do
    expect(Stays::DraftReconstructor.lodging_booking_of(stay.reload).lodging).to eq(grand_duc)
  end
end
