require "rails_helper"

# Bandeau « Aujourd'hui » (Michael 2026-08-28). Il listait les RÉSERVABLES : une
# boucle sur les Booking, puis une autre sur les SpaceBooking. Un séjour qui loue
# un gîte ET des salles y apparaissait DEUX FOIS, sous deux bandeaux différents,
# sans que rien ne dise qu'il s'agissait des mêmes gens. La spec de présentation
# couvre l'agrégation ; celle-ci couvre la PAGE, parce que c'est là que le double
# affichage se voyait.
RSpec.describe "Calendrier — bandeau du jour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-bandeau@les4sources.be", password: "password123") }
  let(:room)  { Room.create!(name: "Chambre B", code: "CHB", level: 1) }
  let(:space) { Space.create!(name: "Grande Salle", code: "GRS", capacity: 1) }

  before { sign_in user }

  it "rend UNE seule carte pour un séjour qui loue un gîte ET des salles" do
    today = Date.today

    customer = Customers::UpsertByEmail.call(
      email: "mixte@example.com",
      attrs: { customer_type: "organization", organization_name: "Groupe Mixte" }
    )
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: today, departure_date: today + 2)

    booking = Booking.create!(firstname: "Groupe", from_date: today, to_date: today + 2,
                              adults: 12, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging")
    Reservation.create!(booking: booking, room: room, date: today)
    StayItem.create!(stay: stay, bookable: booking)

    space_booking = SpaceBooking.create!(firstname: "Groupe", from_date: today, to_date: today + 2,
                                         status: "confirmed", duration: "fullday")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: today, duration: "fullday")
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body.scan(/data-today-stay-card="#{stay.id}"/).size).to eq(1)

    # Et cette carte unique porte bien LES DEUX composants : l'agrégation ne
    # doit pas se payer par la perte des salles.
    carte = response.body[/data-today-stay-card="#{stay.id}".{0,1600}/m]
    expect(carte).to include("Groupe Mixte")
    # Badges par CODE, comme dans la grille (`room_badge` / `space_badge`) : la
    # carte du jour et la cellule du calendrier montrent la même chose.
    expect(carte).to include("CHB")
    expect(carte).to include("GRS")
  end

  it "montre un séjour qui part aujourd'hui, dont la dernière nuit est hier" do
    today = Date.today

    customer = Customers::UpsertByEmail.call(email: "partant@example.com",
                                             attrs: { first_name: "Partant" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: today - 2, departure_date: today)
    booking = Booking.create!(firstname: "Partant", from_date: today - 2, to_date: today,
                              adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging")
    (today - 2).upto(today - 1) { |d| Reservation.create!(booking: booking, room: room, date: d) }
    StayItem.create!(stay: stay, bookable: booking)

    get "/"

    carte = response.body[/data-today-stay-card="#{stay.id}".{0,1600}/m]
    expect(carte).to be_present
    expect(carte).to include("Check-out")
  end
end
