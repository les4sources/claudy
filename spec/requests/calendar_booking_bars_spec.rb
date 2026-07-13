require "rails_helper"

# Issue #10, Phase 1 — barres continues des bookings sur le calendrier racine.
RSpec.describe "Calendrier — barres de booking", type: :request do
  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end

  before { sign_in user }

  # Crée un booking confirmé + ses réservations jour par jour (c'est ce que lit
  # le calendrier), sur les nuits [from, to).
  def confirmed_booking(from:, to:, group: "Groupe test")
    booking = Booking.create!(firstname: "Alex", group_name: group, lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    booking
  end

  it "rend un segment pour un booking intra-semaine" do
    booking = confirmed_booking(from: Date.today.next_occurring(:friday),
                                to: Date.today.next_occurring(:friday) + 2)

    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-booking-segment=\"#{booking.id}\"")
    expect(response.body.scan("data-booking-segment=\"#{booking.id}\"").size).to eq(1)
  end

  it "rend un segment par semaine traversée pour un booking multi-semaines" do
    from = Date.today.next_occurring(:friday)
    booking = confirmed_booking(from: from, to: from + 9) # traverse 2 bords de semaine

    get "/"

    segments = response.body.scan("data-booking-segment=\"#{booking.id}\"").size
    expect(segments).to be >= 2
  end

  it "garde le lien vers la fiche booking" do
    booking = confirmed_booking(from: Date.today.next_occurring(:friday),
                                to: Date.today.next_occurring(:friday) + 2)

    get "/"

    expect(response.body).to include(booking_path(booking))
  end

  it "n'ajoute aucune barre sur la vue Sourciers (anti-régression)" do
    confirmed_booking(from: Date.today.next_occurring(:friday),
                      to: Date.today.next_occurring(:friday) + 2)

    get "/?view=organisation"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-booking-segment")
  end
end
