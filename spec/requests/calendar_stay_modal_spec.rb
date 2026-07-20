require "rails_helper"

# Epic #66, Phase 5 — Les blocs du calendrier ouvrent la MODALE SÉJOUR : un seul
# <dialog> piloté par le contrôleur Stimulus stay-details ; chaque bloc (chambre,
# espace, camping, van) porte un overlay <a href=stay_path> + data-action
# stay-details#open. Le lien historique booking_path/space_booking_path reste dans
# le DOM (anti-régression Phase 4).
RSpec.describe "Calendrier — modale séjour depuis les blocs (epic #66, Phase 5)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { User.create!(email: "agent-modal@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end
  let(:space) { Space.create!(name: "Grande Salle", capacity: 40) }

  before { sign_in user }

  def stay_with_lodging(from:, to:)
    booking = Booking.create!(firstname: "Alex", group_name: "Groupe", lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    [Stays::EnsureForBooking.call(booking), booking]
  end

  describe "infrastructure de la modale" do
    it "rend un unique contrôleur stay-details + le dialog cible" do
      from = Date.today.next_occurring(:friday)
      stay_with_lodging(from: from, to: from + 1)

      get "/"

      expect(response).to have_http_status(:ok)
      # Le wrapper porte désormais stay-details ET stay-merge (epic #81, Phase 2).
      expect(response.body).to match(/data-controller="[^"]*\bstay-details\b[^"]*"/)
      expect(response.body).to include('data-stay-details-target="dialog"')
      expect(response.body).to include('data-stay-details-target="content"')
    end
  end

  describe "bloc chambre" do
    it "porte un overlay cliquable vers stay_path + l'action stay-details#open" do
      from = Date.today.next_occurring(:friday)
      stay, booking = stay_with_lodging(from: from, to: from + 1)

      get "/"

      # Le fil « Activité récente » a quitté la page calendrier (page dédiée,
      # 2026-07-20) : plus rien à exclure, on asserte sur la page entière.
      grid = response.body

      expect(grid).to include('data-action="stay-details#open"')
      expect(grid).to include("href=\"#{stay_path(stay)}\"")
      # Édition unifiée (epic #81, Phase 8) : le lien booking legacy a disparu du
      # bloc dès qu'un séjour vivant le porte — le nom pointe vers la modale.
      expect(grid).not_to include(booking_path(booking))
    end
  end

  describe "bloc espace" do
    it "porte un overlay cliquable vers stay_path de son séjour" do
      from = Date.today.next_occurring(:friday)
      stay, _booking = stay_with_lodging(from: from, to: from + 1)

      space_booking = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe",
                                           from_date: from, to_date: from, status: "confirmed")
      SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
      StayItem.create!(stay: stay, bookable: space_booking)

      get "/"

      grid = response.body
      expect(grid).to include("href=\"#{stay_path(stay)}\"")
      # Édition unifiée (epic #81, Phase 8) : le lien espace legacy a disparu du
      # bloc dès qu'un séjour vivant le porte.
      expect(grid).not_to include(space_booking_path(space_booking))
    end
  end

  describe "bloc camping (désormais cliquable)" do
    it "ouvre la modale de son séjour porteur via un overlay vers stay_path" do
      from = Date.today.next_occurring(:friday)
      to   = from + 2
      camping = CampingBooking.create!(firstname: "Cam", group_name: "Groupe Camping",
                                       from_date: from, to_date: to, people: 4,
                                       status: "confirmed", kind: "tente")
      customer = Customers::UpsertByEmail.call(email: "cam-modal@example.com", attrs: { first_name: "Cam" })
      stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                          arrival_date: from, departure_date: to)
      StayItem.create!(stay: stay, bookable: camping)

      get "/"

      expect(response).to have_http_status(:ok)
      # Camping AVEC séjour : désormais agrégé dans le bloc SÉJOUR UNIFIÉ, qui
      # porte `data-stay-id` et ouvre la modale via l'overlay `stay_path`.
      expect(response.body).to include("data-stay-id=\"#{stay.id}\"")
      expect(response.body).to include("⛺️")
      expect(response.body).to include("href=\"#{stay_path(stay)}\"")
    end
  end
end
