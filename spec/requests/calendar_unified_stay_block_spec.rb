require "rails_helper"

# Bloc SÉJOUR UNIFIÉ — sur le calendrier admin (racine), un séjour multi-composants
# (chambres + espace + camping + van) doit produire UN SEUL bloc par séjour et par
# jour, agrégeant ses composants en badges compacts, au lieu d'un bloc par
# composant. Les occupations SANS séjour gardent leur bloc propre.
RSpec.describe "Calendrier — bloc séjour unifié", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-unified@les4sources.be", password: "password123") }
  let(:room_a) { Room.create!(name: "Chambre A", code: "CHA", level: 1) }
  let(:room_b) { Room.create!(name: "Chambre B", code: "CHB", level: 2) }
  let(:space)  { Space.create!(name: "Grande Salle", code: "GS", capacity: 40) }

  before { sign_in user }

  def hue_for(stay_id)
    ((stay_id * CalendarHelper::GOLDEN_ANGLE) % 360).round
  end

  it "fusionne chambres + espace + camping + van d'un même séjour en UN SEUL bloc par jour" do
    from = Date.today.next_occurring(:friday)

    customer = Customers::UpsertByEmail.call(email: "complet@example.com", attrs: { first_name: "Complet" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from, departure_date: from + 1)

    # Hébergement SANS gîte entier → badges chambres (2 chambres), sur la nuit `from`.
    booking = Booking.create!(firstname: "Complet", group_name: "Séjour Complet", lodging: nil,
                              from_date: from, to_date: from + 1, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    Reservation.create!(booking: booking, room: room_a, date: from)
    Reservation.create!(booking: booking, room: room_b, date: from)
    StayItem.create!(stay: stay, bookable: booking)

    # Espace, camping, van rattachés AU MÊME séjour, même nuit.
    space_booking = SpaceBooking.create!(firstname: "Complet", group_name: "Séjour Complet",
                                         from_date: from, to_date: from, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
    StayItem.create!(stay: stay, bookable: space_booking)

    camping = CampingBooking.create!(firstname: "Complet", group_name: "Séjour Complet",
                                     from_date: from, to_date: from + 1, people: 3,
                                     status: "confirmed", kind: "tente")
    StayItem.create!(stay: stay, bookable: camping)

    van = VanBooking.create!(firstname: "Complet", group_name: "Séjour Complet",
                             from_date: from, to_date: from + 1, vehicles: 2, status: "confirmed")
    StayItem.create!(stay: stay, bookable: van)

    get "/"

    expect(response).to have_http_status(:ok)

    # UN SEUL bloc pour ce séjour ce jour-là (avant : 4 blocs distincts).
    expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)

    # …qui agrège TOUS les composants en badges compacts sur le même bloc.
    expect(response.body).to include("CHA")            # badge chambre A
    expect(response.body).to include("CHB")            # badge chambre B
    expect(response.body).to include("GS")             # badge espace
    expect(response.body).to include("⛺️ 3 pers.")
    expect(response.body).to include("🚐 2 véhicules")

    # Couleur stable par séjour + câblage modale conservés.
    expect(response.body).to include("hsl(#{hue_for(stay.id)}, 65%, 45%)")
    expect(response.body).to include("data-action=\"stay-details#open\"")
    expect(response.body).to include("href=\"#{stay_path(stay)}\"")
  end

  it "affiche 💤 sur une carte de nuitée, jamais sur une carte espaces-seuls" do
    from = Date.today.next_occurring(:friday)

    customer = Customers::UpsertByEmail.call(email: "dodo@example.com", attrs: { first_name: "Dodo" })
    night_stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                              arrival_date: from, departure_date: from + 1)
    booking = Booking.create!(firstname: "Dodo", group_name: "Nuitée", lodging: nil,
                              from_date: from, to_date: from + 1, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    Reservation.create!(booking: booking, room: room_a, date: from)
    StayItem.create!(stay: night_stay, bookable: booking)

    day_customer = Customers::UpsertByEmail.call(email: "journee@example.com", attrs: { first_name: "Journée" })
    day_stay = Stay.create!(customer: day_customer, source: "manual", status: "confirmed",
                            arrival_date: from, departure_date: from)
    sb = SpaceBooking.create!(firstname: "Journée", group_name: "Salle sèche",
                              from_date: from, to_date: from, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: sb, date: from)
    StayItem.create!(stay: day_stay, bookable: sb)

    get "/"

    night_block = response.body[/data-stay-id="#{night_stay.id}".*?<\/div>/m]
    day_block   = response.body[/data-stay-id="#{day_stay.id}".*?<\/div>/m]
    expect(night_block).to include("💤")
    expect(day_block).not_to include("💤")
  end

  # Revue Forge F3 — les cas subtils du split avec/sans séjour, verrouillés.
  it "rend UN bloc pour un séjour espaces-seuls (sans hébergement)" do
    from = Date.today.next_occurring(:friday)

    customer = Customers::UpsertByEmail.call(email: "salle@example.com", attrs: { first_name: "Salle" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from, departure_date: from)
    space_booking = SpaceBooking.create!(firstname: "Salle", group_name: "Salle seule",
                                         from_date: from, to_date: from, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/"

    expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)
    # Pas de double rendu : l'espace AVEC séjour ne sort plus en bloc espace legacy.
    expect(response.body).not_to include("data-space-booking-day-entry=\"#{space_booking.id}\"")
  end

  it "rend le bloc séjour un jour où seul l'ESPACE occupe (aucune chambre ce jour-là)" do
    from = Date.today.next_occurring(:friday)

    customer = Customers::UpsertByEmail.call(email: "decale@example.com", attrs: { first_name: "Décalé" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: from, departure_date: from + 2)
    booking = Booking.create!(firstname: "Décalé", group_name: "Séjour Décalé", lodging: nil,
                              from_date: from, to_date: from + 1, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    Reservation.create!(booking: booking, room: room_a, date: from) # chambre : nuit `from` uniquement
    StayItem.create!(stay: stay, bookable: booking)
    space_booking = SpaceBooking.create!(firstname: "Décalé", group_name: "Séjour Décalé",
                                         from_date: from + 2, to_date: from + 2, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from + 2) # jour du départ
    StayItem.create!(stay: stay, bookable: space_booking)

    get "/"

    # Deux jours rendus pour ce séjour : la nuit chambre ET le jour espace-seul.
    expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(2)
    # Compteur borné (Forge F1) : le jour du départ n'affiche jamais (3/2).
    expect(response.body).not_to include("(3/2)")
  end

  it "laisse un espace SANS séjour garder son bloc espace legacy" do
    from = Date.today.next_occurring(:friday)

    space_booking = SpaceBooking.create!(firstname: "Externe", group_name: "Salle externe",
                                         from_date: from, to_date: from, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
    # PAS de Stay / StayItem.

    get "/"

    expect(response.body).to include("data-space-booking-day-entry=\"#{space_booking.id}\"")
  end

  it "laisse un booking SANS séjour garder son propre bloc et son lien fiche" do
    from = Date.today.next_occurring(:friday)

    booking = Booking.create!(firstname: "Legacy", group_name: "Sans séjour", lodging: nil,
                              from_date: from, to_date: from + 1, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    Reservation.create!(booking: booking, room: room_a, date: from)
    # PAS de Stay / StayItem.

    get "/"

    expect(response).to have_http_status(:ok)
    # Bloc legacy conservé : son entrée par jour + le lien vers la fiche booking.
    expect(response.body).to include("data-booking-day-entry=\"#{booking.id}\"")
    expect(response.body).to include(booking_path(booking))
  end
end
