require "rails_helper"

# Séjours rendus dans les cellules de jour du calendrier racine, entre les
# avatars veilleurs et les notes (remplace les barres hebdo de l'issue #10).
RSpec.describe "Calendrier — séjours dans les cellules", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end

  before { sign_in user }

  # Le calendrier racine montre le mois courant, et ces specs réservent au
  # « vendredi qui vient » : en fin de mois, il tombe hors de la grille (le
  # 30 octobre 2026, le vendredi suivant est le 6 novembre). Un mercredi en
  # milieu de mois garde ce vendredi dans le mois affiché.
  around { |example| travel_to(Time.zone.local(2026, 10, 14, 10)) { example.run } }

  # Crée un booking confirmé + ses réservations jour par jour (c'est ce que lit
  # le calendrier), sur les nuits [from, to).
  def confirmed_booking(from:, to:, group: "Groupe test")
    booking = Booking.create!(firstname: "Alex", group_name: group, lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    booking
  end

  it "rend une entrée séjour dans la cellule de chaque jour réservé" do
    from = Date.today.next_occurring(:friday)
    booking = confirmed_booking(from: from, to: from + 2)

    get "/"

    expect(response).to have_http_status(:ok)
    entries = response.body.scan("data-booking-day-entry=\"#{booking.id}\"").size
    expect(entries).to eq(2)
  end

  it "rend l'entrée séjour à l'intérieur du conteneur bookings de la cellule, avant les notes" do
    from = Date.today.next_occurring(:friday)
    booking = confirmed_booking(from: from, to: from + 1)

    get "/"

    body = response.body
    container_index = body.index("id=\"bookings-#{from.iso8601}\"")
    notes_index = body.index("id=\"notes-#{from}\"")
    entry_index = body.index("data-booking-day-entry=\"#{booking.id}\"")
    expect(container_index).not_to be_nil
    expect(entry_index).to be > container_index
    expect(entry_index).to be < notes_index
  end

  it "garde le lien vers la fiche booking" do
    booking = confirmed_booking(from: Date.today.next_occurring(:friday),
                                to: Date.today.next_occurring(:friday) + 2)

    get "/"

    expect(response.body).to include(booking_path(booking))
  end

  it "ne rend plus aucune barre hebdomadaire" do
    from = Date.today.next_occurring(:friday)
    confirmed_booking(from: from, to: from + 9)

    get "/"

    expect(response.body).not_to include("data-booking-segment")
  end

  it "laisse la vue Sourciers inchangée (anti-régression)" do
    confirmed_booking(from: Date.today.next_occurring(:friday),
                      to: Date.today.next_occurring(:friday) + 2)

    get "/?view=organisation"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-booking-day-entry")
  end
end
