require "rails_helper"

# Issue #99 — Retrait final des écrans d'édition legacy Booking/SpaceBooking.
# `bookings#edit` et `space_bookings#edit` sont désormais de PURES redirections :
#   - Stay VIVANT → 302 vers `edit_stay_path` (édition unifiée, seul chemin) ;
#   - PAS de Stay vivant (cas résiduel : séjour soft-deleté à la main) → 302 vers
#     la fiche `#show` avec une alerte invitant à relancer `rake stays:backfill_missing`.
# Plus JAMAIS de rendu du formulaire d'édition legacy (il n'existe plus).
RSpec.describe "Édition unifiée — edit → redirection (issue #99)", type: :request do
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

  def orphan_booking(from:)
    booking = Booking.create!(firstname: "Sans", group_name: "Séjour", lodging: lodging,
                              from_date: from, to_date: from + 1, adults: 1, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0)
    Reservation.create!(booking: booking, room: room, date: from)
    booking
  end

  def space_booking_with_stay(on:)
    space_booking = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe", tier: "neutre",
                                         from_date: on, to_date: on, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: on)
    [space_booking, Stays::EnsureForSpaceBooking.call(space_booking)]
  end

  def orphan_space_booking(on:)
    space_booking = SpaceBooking.create!(firstname: "Sans", group_name: "Séjour", tier: "neutre",
                                         from_date: on, to_date: on, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: on)
    space_booking
  end

  describe "GET /bookings/:id/edit" do
    it "redirige vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      booking, stay = booking_with_stay(from: from, to: from + 1)

      get edit_booking_path(booking)

      expect(response).to redirect_to(edit_stay_path(stay))
    end

    it "redirige vers la fiche avec alerte quand le booking n'a pas de Stay vivant (cas résiduel)" do
      from = Date.today.next_occurring(:friday)
      booking = orphan_booking(from: from)

      get edit_booking_path(booking)

      expect(response).to redirect_to(booking_path(booking))
      follow_redirect!
      expect(response.body).to include("backfill_missing")
    end
  end

  describe "GET /space_bookings/:id/edit" do
    it "redirige vers l'édition du séjour quand un Stay vivant existe" do
      from = Date.today.next_occurring(:friday)
      space_booking, stay = space_booking_with_stay(on: from)

      get edit_space_booking_path(space_booking)

      expect(response).to redirect_to(edit_stay_path(stay))
    end

    it "redirige vers la fiche avec alerte quand la résa d'espace n'a pas de Stay vivant (cas résiduel)" do
      from = Date.today.next_occurring(:friday)
      space_booking = orphan_space_booking(on: from)

      get edit_space_booking_path(space_booking)

      expect(response).to redirect_to(space_booking_path(space_booking))
      follow_redirect!
      expect(response.body).to include("backfill_missing")
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

    it "disparaît quand le booking n'a pas de Stay vivant (un lien vers la fiche serait un no-op)" do
      from = Date.today.next_occurring(:friday)
      booking = orphan_booking(from: from)

      get booking_path(booking)

      expect(response.body).not_to include(edit_booking_path(booking))
      expect(response.body).not_to include("Mettre à jour")
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

    it "disparaît quand la résa d'espace n'a pas de Stay vivant (un lien vers la fiche serait un no-op)" do
      from = Date.today.next_occurring(:friday)
      space_booking = orphan_space_booking(on: from)

      get space_booking_path(space_booking)

      expect(response.body).not_to include(edit_space_booking_path(space_booking))
      expect(response.body).not_to include("Mettre à jour")
    end
  end
end
