require "rails_helper"

RSpec.describe Lodging, type: :model do
  # Le Grand-Duc = La Hulotte + La Chevêche. Reserving any entangled unit makes
  # the others unavailable, derived on the fly with no stored blocking (AC-24/25/51).
  let(:grand_duc) { Lodging.create!(name: "Le Grand-Duc", price_night_cents: 12_000) }
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
  let(:cheveche) { Lodging.create!(name: "La Chevêche", price_night_cents: 8_000) }

  let(:grand_duc_room) { make_room(grand_duc, "GD") }
  let(:hulotte_room) { make_room(hulotte, "HU") }
  let(:cheveche_room) { make_room(cheveche, "CH") }

  let(:window) { [Date.new(2026, 8, 1), Date.new(2026, 8, 3)] }

  def make_room(lodging, code)
    room = Room.create!(name: "Chambre #{code}", level: 1)
    lodging.rooms << room
    room
  end

  def reserve(room, from:, to:)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed")
    (from..to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    booking
  end

  before do
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: hulotte)
    LodgingComposition.create!(composite_lodging: grand_duc, component_lodging: cheveche)
    grand_duc_room && hulotte_room && cheveche_room
  end

  it "knows which lodgings are composite vs component" do
    expect(grand_duc).to be_composite
    expect(hulotte).to be_component
    expect(grand_duc).not_to be_component
  end

  it "marks the composite unavailable when a component is booked (AC-24)" do
    reserve(hulotte_room, from: window.first, to: window.last)

    expect(grand_duc.available_between?(*window)).to be(false)
    expect(cheveche.self_available_between?(*window)).to be(true)
    # Booking only Hulotte must NOT block its sibling Chevêche.
    expect(cheveche.available_between?(*window)).to be(true)
  end

  it "marks a component unavailable when the composite is booked (AC-25)" do
    reserve(grand_duc_room, from: window.first, to: window.last)

    expect(hulotte.available_between?(*window)).to be(false)
    expect(cheveche.available_between?(*window)).to be(false)
  end

  it "derives availability with no stored blocking (AC-51)" do
    reserve(hulotte_room, from: window.first, to: window.last)

    expect {
      grand_duc.available_between?(*window)
      grand_duc.available_on?(window.first)
    }.not_to change { [Reservation.count, Unavailability.count] }
  end
end
