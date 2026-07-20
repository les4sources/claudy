require "rails_helper"

# Section veilleur du jour (2026-07-20) : Check-in / Check-out / Séjour en cours
# visibles et distincts — y compris les CHECK-OUT du jour, qui n'apparaissaient
# jamais (un départ du jour n'a pas de nuitée aujourd'hui).
RSpec.describe "Calendrier — section veilleur du jour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "veilleur@les4sources.be", password: "password123") }
  let(:room) { Room.create!(name: "Chambre V", code: "CHV", level: 1) }

  before { sign_in user }

  def booking_with_reservations(from:, to:, name:)
    booking = Booking.create!(firstname: name, group_name: name, lodging: nil,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |d| Reservation.create!(booking: booking, room: room, date: d) }
    booking
  end

  it "affiche les cartes Check-out (départ du jour), Check-in et Séjour en cours" do
    booking_with_reservations(from: Date.today - 2, to: Date.today, name: "Partants")
    booking_with_reservations(from: Date.today, to: Date.today + 2, name: "Arrivants")
    booking_with_reservations(from: Date.today - 1, to: Date.today + 1, name: "Installés")

    get "/"

    expect(response).to have_http_status(:ok)
    header = response.body[/Veilleur.*?js-calendar-col-highlight/m] || response.body
    expect(header).to include("🧳 Check-out")
    expect(header).to include("Partants")
    expect(header).to include("🛎️ Check-in")
    expect(header).to include("Arrivants")
    expect(header).to include("🛏️ Séjour en cours")
    expect(header).to include("Installés")
    expect(response.body).not_to include("Hébergement en cours")
  end
end
