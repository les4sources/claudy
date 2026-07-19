require "rails_helper"

# Epic #81, Phase 8 — Édition unifiée. L'édition d'un Booking/SpaceBooking
# existant passe par le form séjour : `bookings#edit` et `space_bookings#edit`
# redirigent (302) vers `edit_stay_path` dès qu'un Stay VIVANT porte le record.
# Sans Stay (backfill Phase 1 pas encore tourné en prod), l'écran legacy est
# encore servi — fallback orphelin, appelé à disparaître en Phase 9.
RSpec.describe "Édition unifiée — redirection edit → séjour (epic #81, Phase 8)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { User.create!(email: "agent-unified-edit@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end
  let(:space) { Space.create!(name: "Grande Salle", capacity: 40) }

  before { sign_in user }

  def booking_with_stay(from:, to:)
    booking = Booking.create!(firstname: "Alex", group_name: "Groupe", lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    [booking, Stays::EnsureForBooking.call(booking)]
  end

  def space_booking_with_stay(on:)
    space_booking = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe", tier: "neutre",
                                         from_date: on, to_date: on, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: on)
    [space_booking, Stays::EnsureForSpaceBooking.call(space_booking)]
  end

  describe "GET /bookings/:id/edit" do
    it "redirige vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      booking, stay = booking_with_stay(from: from, to: from + 1)

      get edit_booking_path(booking)

      expect(response).to redirect_to(edit_stay_path(stay))
    end

    it "sert encore l'écran legacy quand le booking n'a pas de Stay (fallback orphelin)" do
      from = Date.today.next_occurring(:friday)
      booking = Booking.create!(firstname: "Sans", group_name: "Séjour", lodging: lodging,
                                from_date: from, to_date: from + 1, adults: 1, children: 0, babies: 0,
                                status: "confirmed", booking_type: "lodging", price_cents: 0)
      Reservation.create!(booking: booking, room: room, date: from)

      get edit_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(booking_path(booking)) # le form legacy soumet toujours
    end
  end

  describe "bouton « Mettre à jour » de la fiche booking" do
    it "pointe vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      booking, stay = booking_with_stay(from: from, to: from + 1)

      get booking_path(booking)

      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(edit_booking_path(booking))
    end

    it "garde le lien legacy quand le booking n'a pas de Stay (fallback orphelin)" do
      from = Date.today.next_occurring(:friday)
      booking = Booking.create!(firstname: "Sans", group_name: "Séjour", lodging: lodging,
                                from_date: from, to_date: from + 1, adults: 1, children: 0, babies: 0,
                                status: "confirmed", booking_type: "lodging", price_cents: 0)
      Reservation.create!(booking: booking, room: room, date: from)

      get booking_path(booking)

      expect(response.body).to include(edit_booking_path(booking))
    end
  end

  describe "bouton « Mettre à jour » de la fiche résa d'espace" do
    it "pointe vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      space_booking, stay = space_booking_with_stay(on: from)

      get space_booking_path(space_booking)

      expect(response.body).to include(edit_stay_path(stay))
      expect(response.body).not_to include(edit_space_booking_path(space_booking))
    end

    it "garde le lien legacy quand la résa d'espace n'a pas de Stay (fallback orphelin)" do
      from = Date.today.next_occurring(:friday)
      space_booking = SpaceBooking.create!(firstname: "Sans", group_name: "Séjour", tier: "neutre",
                                           from_date: from, to_date: from, status: "confirmed")
      SpaceReservation.create!(space: space, space_booking: space_booking, date: from)

      get space_booking_path(space_booking)

      expect(response.body).to include(edit_space_booking_path(space_booking))
    end
  end

  describe "GET /space_bookings/:id/edit" do
    it "redirige vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      space_booking, stay = space_booking_with_stay(on: from)

      get edit_space_booking_path(space_booking)

      expect(response).to redirect_to(edit_stay_path(stay))
    end

    it "sert encore l'écran legacy quand la résa d'espace n'a pas de Stay (fallback orphelin)" do
      from = Date.today.next_occurring(:friday)
      space_booking = SpaceBooking.create!(firstname: "Sans", group_name: "Séjour",
                                           from_date: from, to_date: from, status: "confirmed")
      SpaceReservation.create!(space: space, space_booking: space_booking, date: from)

      get edit_space_booking_path(space_booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(space_booking_path(space_booking)) # form legacy soumet toujours
    end
  end
end
