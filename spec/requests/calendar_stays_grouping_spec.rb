require "rails_helper"

# Epic #66, Phase 4 — Le calendrier racine bascule sur les SÉJOURS : il regroupe
# et colore les occupations PAR `stay_id` (couleur stable par séjour, style
# inline), tout en gardant UN BLOC PAR RESSOURCE occupée (chambre / espace /
# camping-van) — ce qui préserve la représentation qui porte le veto Grand-Duc.
RSpec.describe "Calendrier — regroupement par séjour (epic #66, Phase 4)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end
  let(:space) { Space.create!(name: "Grande Salle", capacity: 5) }

  before { sign_in user }

  # Teinte attendue pour un séjour — même formule que CalendarHelper.
  def hue_for(stay_id)
    ((stay_id * CalendarHelper::GOLDEN_ANGLE) % 360).round
  end

  # Booking confirmé + ses réservations jour par jour + son Stay (via le service
  # d'attachement réel, comme en production admin/OTA).
  def stay_with_lodging(from:, to:, group: "Groupe Hébergement")
    booking = Booking.create!(firstname: "Alex", group_name: group, lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    stay = Stays::EnsureForBooking.call(booking)
    [stay, booking]
  end

  describe "regroupement + couleur par séjour" do
    it "pose data-stay-id et la couleur inline stable du séjour sur le bloc chambre" do
      from = Date.today.next_occurring(:friday)
      stay, _booking = stay_with_lodging(from: from, to: from + 1)

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-stay-id=\"#{stay.id}\"")
      expect(response.body).to include("hsl(#{hue_for(stay.id)}, 65%, 45%)")
    end

    it "fusionne un séjour MULTI-RESSOURCES (hébergement + espace) en UN SEUL bloc" do
      from = Date.today.next_occurring(:friday)
      stay, _booking = stay_with_lodging(from: from, to: from + 1)

      # Un espace rattaché AU MÊME séjour (multi-ressources).
      space_booking = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe Hébergement",
                                           from_date: from, to_date: from, status: "confirmed")
      SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
      StayItem.create!(stay: stay, bookable: space_booking)

      get "/"

      # Bloc SÉJOUR UNIFIÉ : un seul `data-stay-id` ce jour-là (avant : un bloc
      # par ressource, donc plusieurs). L'hébergement ET l'espace sont agrégés…
      expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(1)
      # …le badge espace (orange) figure bien dans ce bloc unifié…
      expect(response.body).to include("bg-orange-100")
      # …et la teinte stable du séjour colore le bloc.
      expect(response.body).to include("hsl(#{hue_for(stay.id)}, 65%, 45%)")
    end

    it "attribue des couleurs DISTINCTES à deux séjours différents" do
      from = Date.today.next_occurring(:friday)
      stay_a, _a = stay_with_lodging(from: from, to: from + 1, group: "Séjour A")
      # Deuxième chambre/hébergement pour un second séjour, même nuit.
      other_room = Room.create!(name: "Chambre 2", level: 1)
      lodging.rooms << other_room
      booking_b = Booking.create!(firstname: "Bea", group_name: "Séjour B", lodging: lodging,
                                  from_date: from, to_date: from + 1, adults: 1, children: 0, babies: 0,
                                  status: "confirmed", booking_type: "lodging", price_cents: 0)
      Reservation.create!(booking: booking_b, room: other_room, date: from)
      stay_b = Stays::EnsureForBooking.call(booking_b)

      get "/"

      expect(hue_for(stay_a.id)).not_to eq(hue_for(stay_b.id))
      expect(response.body).to include("hsl(#{hue_for(stay_a.id)}, 65%, 45%)")
      expect(response.body).to include("hsl(#{hue_for(stay_b.id)}, 65%, 45%)")
    end
  end

  describe "occupations chambres — anti-régression veto Grand-Duc" do
    it "rend un bloc séjour par jour réservé, la source du veto restant les Reservation en base" do
      from = Date.today.next_occurring(:friday)
      stay, booking = stay_with_lodging(from: from, to: from + 2)

      get "/"

      # Deux nuits réservées → deux cellules du jour → deux blocs séjour unifiés.
      expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(2)
      # La VRAIE source de vérité du veto reste la table Reservation (inchangée
      # par la fusion d'affichage) : une réservation de chambre par nuit.
      expect(Reservation.where(booking: booking).count).to eq(2)
      # Édition unifiée (epic #81, Phase 8) : le bloc pointe vers la modale séjour,
      # plus vers la fiche booking legacy. On borne à la grille (le flux d'activité,
      # hors scope, garde son lien booking historique).
      grid = response.body.split("Activité récente").first
      expect(grid).to include(stay_path(stay))
      expect(grid).not_to include(booking_path(booking))
    end

    it "retombe sur la couleur historique (par type) pour un booking SANS séjour" do
      from = Date.today.next_occurring(:friday)
      booking = Booking.create!(firstname: "Legacy", group_name: "Sans séjour", lodging: lodging,
                                from_date: from, to_date: from + 1, adults: 2, children: 0, babies: 0,
                                status: "confirmed", booking_type: "lodging", price_cents: 0)
      Reservation.create!(booking: booking, room: room, date: from)
      # PAS de Stay attaché.

      get "/"

      # Couleur historique (emerald pour un lodging confirmé), pas de data-stay-id.
      expect(response.body).to include("border-emerald-500")
      expect(response.body).to include("data-booking-day-entry=\"#{booking.id}\"")
    end
  end

  describe "camping / van agrégés, groupés par séjour" do
    it "rend un bloc séjour par nuit occupée avec la chip camping agrégée, coloré par le séjour" do
      from = Date.today.next_occurring(:friday)
      to   = from + 2 # 2 nuits
      camping = CampingBooking.create!(firstname: "Cam", group_name: "Groupe Camping",
                                       from_date: from, to_date: to, people: 4,
                                       status: "confirmed", kind: "tente")
      customer = Customers::UpsertByEmail.call(email: "cam@example.com", attrs: { first_name: "Cam" })
      stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                          arrival_date: from, departure_date: to)
      StayItem.create!(stay: stay, bookable: camping)

      get "/"

      expect(response).to have_http_status(:ok)
      # Bloc séjour unifié : une entrée par nuit (2), colorée par le séjour, avec
      # la chip camping agrégée (avant : un bloc « Camping » distinct par nuit).
      expect(response.body.scan("data-stay-id=\"#{stay.id}\"").size).to eq(2)
      expect(response.body).to include("hsl(#{hue_for(stay.id)}, 65%, 45%)")
      expect(response.body).to include("Groupe Camping")
      expect(response.body).to include("⛺ Camping · 4 pers.")
    end
  end

  describe "vue Sourciers (anti-régression)" do
    it "reste inchangée — aucun regroupement séjour n'y fuit" do
      from = Date.today.next_occurring(:friday)
      stay_with_lodging(from: from, to: from + 1)

      get "/?view=organisation"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-booking-day-entry")
      expect(response.body).not_to include("data-camping-booking-entry")
    end
  end
end
