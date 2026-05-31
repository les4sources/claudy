require "rails_helper"

RSpec.describe Lodging, type: :model do
  # Le Grand-Duc = La Hulotte + La Chevêche. In production the composite SHARES
  # its components' physical rooms: Grand-Duc owns the UNION of the component
  # rooms (Chevêche rooms + Hulotte rooms). Occupancy therefore propagates
  # through the shared room reservations themselves, so availability is simply
  # each lodging's own rooms being free — no entanglement veto. See
  # Lodging#available_between?.
  let(:grand_duc) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 12_000) }
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
  let(:cheveche) { Lodging.create!(name: "La Chevêche", price_night_cents: 8_000) }

  let(:hulotte_room) { Room.create!(name: "Chambre HU", level: 1) }
  let(:cheveche_room) { Room.create!(name: "Chambre CH", level: 1) }

  let(:window) { [Date.new(2026, 8, 1), Date.new(2026, 8, 3)] }

  # Reserve a lodging on all of its (possibly shared) rooms for the window.
  def reserve(lodging, from:, to:)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed", lodging: lodging)
    lodging.rooms.each do |room|
      (from..to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    end
    booking
  end

  before do
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: hulotte)
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: cheveche)
    # Shared rooms: each component owns its room; the composite owns the union.
    hulotte.rooms << hulotte_room
    cheveche.rooms << cheveche_room
    grand_duc.rooms << hulotte_room
    grand_duc.rooms << cheveche_room
  end

  it "knows which lodgings are composite vs component" do
    expect(grand_duc).to be_composite
    expect(hulotte).to be_component
    expect(grand_duc).not_to be_component
  end

  it "marks the composite unavailable when a component is booked (AC-24)" do
    reserve(cheveche, from: window.first, to: window.last)

    expect(grand_duc.available_between?(*window)).to be(false)
    # Booking the Chevêche must NOT block its sibling Hulotte.
    # Regression guard for Sentry 7296086238 (booking 810): editing a Hulotte
    # booking failed with "Cet hébergement n'est pas disponible à cette date."
    # because the Grand-Duc (sharing the Chevêche room) wrongly vetoed it.
    expect(hulotte.available_between?(*window)).to be(true)
  end

  it "marks both components unavailable when the composite is booked (AC-25)" do
    reserve(grand_duc, from: window.first, to: window.last)

    expect(hulotte.available_between?(*window)).to be(false)
    expect(cheveche.available_between?(*window)).to be(false)
  end

  it "blocks the composite when a component is booked, leaving the sibling free" do
    reserve(hulotte, from: window.first, to: window.last)

    expect(grand_duc.available_between?(*window)).to be(false)
    expect(cheveche.available_between?(*window)).to be(true)
  end

  it "derives availability with no stored blocking / mirror reservation (AC-51)" do
    reserve(cheveche, from: window.first, to: window.last)

    # Only the Chevêche's own room got reservations — no mirror rows for the composite.
    expect(Reservation.where(room: cheveche_room).count).to eq(3)
    expect {
      grand_duc.available_between?(*window)
      grand_duc.available_on?(window.first)
      hulotte.available_between?(*window)
    }.not_to change { [Reservation.count, Unavailability.count] }
  end
end
