require "rails_helper"

# AC-T2-32 : pas de blocage OTA (Q6). La disponibilité de /reservation ne se
# calcule QUE sur les Stays/Bookings natifs Claudy (Reservation de Booking
# confirmé). Une date occupée uniquement « côté OTA » (sans Booking natif) ne
# rend pas l'hébergement indisponible.
RSpec.describe "Disponibilité /reservation — pas de blocage OTA (AC-T2-32)", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  let(:from) { Date.today + 50 }
  let(:to)   { Date.today + 52 }

  it "reste disponible quand aucune réservation Claudy native n'occupe la plage" do
    expect(hulotte.available_between?(from, to)).to be(true)
  end

  it "devient indisponible dès qu'un Booking Claudy confirmé occupe la plage" do
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed")
    (from..to).each { |d| Reservation.create!(booking: booking, room: hulotte.rooms.first, date: d) }

    expect(hulotte.available_between?(from, to)).to be(false)
  end

  it "n'est pas bloqué par un Booking non confirmé (pending) — seul le confirmé bloque" do
    pending_booking = Booking.create!(firstname: "Pend", from_date: from, to_date: to, adults: 1, status: "pending")
    (from..to).each { |d| Reservation.create!(booking: pending_booking, room: hulotte.rooms.first, date: d) }

    expect(hulotte.available_between?(from, to)).to be(true)
  end
end
