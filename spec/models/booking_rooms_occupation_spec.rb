require "rails_helper"

# Epic #81, Phase 5 — `Booking#rooms_only_occupation?` dérive le mode d'occupation
# (gîte entier vs chambres seules) des Reservation comparées à l'ensemble des
# chambres du gîte, sans drapeau persisté. Sert au préremplissage du form édition.
RSpec.describe Booking, "#rooms_only_occupation? (epic #81, Phase 5)", type: :model do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << Room.create!(name: "Chambre 2", level: 1)
    lodging.rooms << Room.create!(name: "Chambre 3", level: 1)
    lodging
  end

  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 3) }

  def booking_reserving(rooms)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed", lodging: hulotte)
    rooms.each { |room| (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) } }
    booking
  end

  it "est faux pour une occupation de gîte ENTIER (toutes les chambres réservées)" do
    booking = booking_reserving(hulotte.rooms.to_a)
    expect(booking.rooms_only_occupation?).to be(false)
  end

  it "est vrai pour un SOUS-ENSEMBLE de chambres" do
    booking = booking_reserving(hulotte.rooms.first(2))
    expect(booking.rooms_only_occupation?).to be(true)
  end

  it "est faux sans aucune réservation de chambre" do
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed", lodging: hulotte)
    expect(booking.rooms_only_occupation?).to be(false)
  end

  it "est faux sans hébergement rattaché" do
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed")
    expect(booking.rooms_only_occupation?).to be(false)
  end
end
