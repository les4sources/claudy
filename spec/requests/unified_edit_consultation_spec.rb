require "rails_helper"

# Epic #81, Phase 8 — Édition unifiée, liens de CONSULTATION sur les pages SANS
# la modale séjour (day, index). Décision : ces pages renvoient vers le form
# séjour (`edit_stay_path`, page pleine avec layout) quand un Stay VIVANT porte
# le record — `stays#show` rend un fragment sans layout, inexploitable en
# navigation directe, et le form séjour EST le point d'entrée unifié de l'epic.
# Sans Stay VIVANT (cas résiduel post-backfill : séjour soft-deleté à la main),
# le lien mène à la fiche `#show` — l'édition legacy n'existe plus (issue #99) —
# et aucune page ne rend de lien mort.
RSpec.describe "Édition unifiée — consultation hors modale (epic #81, Phase 8)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { User.create!(email: "agent-unified-conso@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    # `code` valide : la vue jour rend l'image `images/rooms/#{code}.jpg` (présente
    # dans le manifest vite-test).
    r = Room.create!(name: "Chambre 1", level: 1, code: "BAL")
    lodging.rooms << r
    r
  end
  let(:space) { Space.create!(name: "Grande Salle", capacity: 40) }

  before { sign_in user }

  def confirmed_booking(from:, to:)
    booking = Booking.create!(firstname: "Alex", group_name: "Groupe", lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    booking
  end

  def confirmed_space_booking(on:)
    sb = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe", tier: "neutre",
                              from_date: on, to_date: on, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: sb, date: on)
    sb
  end

  describe "vue jour (pages#day)" do
    it "renvoie le lien d'un booking à séjour vers le form séjour (pas la fiche legacy)" do
      from = Date.today.next_occurring(:friday)
      booking = confirmed_booking(from: from, to: from + 1)
      stay = Stays::EnsureForBooking.call(booking)

      get day_details_path(date: from.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(booking_path(booking))
    end

    it "renvoie vers la fiche show (jamais l'édition) quand le booking n'a pas de séjour" do
      from = Date.today.next_occurring(:friday)
      booking = confirmed_booking(from: from, to: from + 1)

      get day_details_path(date: from.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking_path(booking))
      # booking_path est une sous-chaîne de edit_booking_path : on distingue.
      expect(response.body).not_to include(edit_booking_path(booking))
    end

    it "renvoie le lien d'une résa d'espace à séjour vers le form séjour" do
      from = Date.today.next_occurring(:friday)
      sb = confirmed_space_booking(on: from)
      stay = Stays::EnsureForSpaceBooking.call(sb)

      get day_details_path(date: from.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(space_booking_path(sb))
    end

    it "renvoie vers la fiche show (jamais l'édition) quand la résa d'espace n'a pas de séjour" do
      from = Date.today.next_occurring(:friday)
      sb = confirmed_space_booking(on: from)

      get day_details_path(date: from.iso8601)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(space_booking_path(sb))
      expect(response.body).not_to include(edit_space_booking_path(sb))
    end
  end

  describe "index hébergements (bookings#index)" do
    it "renvoie un booking à séjour vers le form séjour (pas la fiche legacy)" do
      from = Date.today.next_occurring(:friday)
      booking = confirmed_booking(from: from, to: from + 2)
      stay = Stays::EnsureForBooking.call(booking)

      get bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(booking_path(booking))
    end

    it "renvoie vers la fiche show pour un booking sans séjour (aucun lien mort)" do
      from = Date.today.next_occurring(:friday)
      booking = confirmed_booking(from: from, to: from + 2)

      get bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking_path(booking))
      # booking_path est une sous-chaîne de edit_booking_path : on distingue.
      expect(response.body).not_to include(edit_booking_path(booking))
    end
  end

  describe "toast « autres réservations » (pages#other_bookings)" do
    it "renvoie un booking à séjour vers le form séjour" do
      from = Date.today.next_occurring(:friday)
      other = confirmed_booking(from: from, to: from + 2)
      stay = Stays::EnsureForBooking.call(other)

      get "/pages/other_bookings", params: { from_date: from.iso8601, to_date: (from + 2).iso8601, booking_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(booking_path(other))
    end

    it "renvoie vers la fiche show pour un booking sans séjour" do
      from = Date.today.next_occurring(:friday)
      other = confirmed_booking(from: from, to: from + 2)

      get "/pages/other_bookings", params: { from_date: from.iso8601, to_date: (from + 2).iso8601, booking_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking_path(other))
      # booking_path est une sous-chaîne de edit_booking_path : on distingue.
      expect(response.body).not_to include(edit_booking_path(other))
    end
  end

  describe "toast « autres réservations » espaces (pages#other_space_bookings)" do
    it "renvoie une résa d'espace à séjour vers le form séjour" do
      from = Date.today.next_occurring(:friday)
      sb = confirmed_space_booking(on: from)
      stay = Stays::EnsureForSpaceBooking.call(sb)

      get "/pages/other_space_bookings", params: { from_date: from.iso8601, to_date: (from + 1).iso8601, space_booking_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(space_booking_path(sb))
    end
  end

  describe "index espaces (space_bookings#index)" do
    it "renvoie une résa d'espace à séjour vers le form séjour" do
      from = Date.today.next_occurring(:friday)
      sb = confirmed_space_booking(on: from)
      stay = Stays::EnsureForSpaceBooking.call(sb)

      get space_bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(space_booking_path(sb))
    end

    it "renvoie vers la fiche show pour une résa d'espace sans séjour" do
      from = Date.today.next_occurring(:friday)
      sb = confirmed_space_booking(on: from)

      get space_bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(space_booking_path(sb))
      expect(response.body).not_to include(edit_space_booking_path(sb))
    end
  end
end
