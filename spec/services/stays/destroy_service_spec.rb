require "rails_helper"

# Issue #99 — Supprimer un séjour libère TOUTES ses occupations.
# Le soft-delete du Stay cascade nativement sur ses stay_items + meal_orders,
# mais PAS sur les bookables : sans `Stays::DestroyService`, Booking/SpaceBooking
# (et leurs Reservation/SpaceReservation) restaient VIVANTS → blocs fantômes qui
# occupaient le calendrier et posaient le veto de dispo, sans séjour d'attache.
RSpec.describe Stays::DestroyService do
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:room) do
    r = Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << r
    r
  end
  let(:space) { Space.create!(name: "Grande Salle", capacity: 1) }

  # Séjour multi-éléments : un hébergement (Booking + Reservations de chambre) et
  # une réservation d'espace (SpaceBooking + SpaceReservation), rattachés au MÊME
  # Stay, plus un Payment encaissé.
  def build_multi_element_stay(from:, to:)
    booking = Booking.create!(firstname: "Alex", group_name: "Groupe", lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 10_000)
    (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    stay = Stays::EnsureForBooking.call(booking)

    space_booking = SpaceBooking.create!(firstname: "Alex", group_name: "Groupe", tier: "neutre",
                                         from_date: from, to_date: from, status: "confirmed",
                                         price_cents: 5_000)
    SpaceReservation.create!(space: space, space_booking: space_booking, date: from)
    stay.stay_items.create!(bookable: space_booking)

    payment = Payment.create!(booking: booking, stay: stay, amount_cents: 3_000,
                              payment_method: "cash", status: "paid")

    [stay, booking, space_booking, payment]
  end

  describe "#run" do
    it "soft-delete le séjour, ses bookables, et libère calendrier + veto ; conserve les paiements" do
      from = Date.today + 400
      to   = from + 2
      stay, booking, space_booking, payment = build_multi_element_stay(from: from, to: to)

      # Occupations bien vivantes AVANT.
      expect(space.available_on?(from)).to be(false) # espace occupé (capacity 1)
      expect(Reservation.where(booking_id: booking.id).count).to eq(2)

      result = described_class.new(stay: stay).run

      expect(result).to be(true)

      # Séjour + bookables soft-deletés.
      expect(Stay.find_by(id: stay.id)).to be_nil                 # default_scope live
      expect(Booking.find_by(id: booking.id)).to be_nil
      expect(SpaceBooking.find_by(id: space_booking.id)).to be_nil

      # PLUS AUCUNE occupation vivante : chambres rendues (Reservation soft-delete
      # via cascade), lignes SpaceReservation retirées.
      expect(Reservation.where(booking_id: booking.id).count).to eq(0)
      live_sr = ActiveRecord::Base.connection.select_value(
        "SELECT COUNT(*) FROM space_reservations WHERE space_booking_id = #{space_booking.id} AND deleted_at IS NULL"
      )
      expect(live_sr.to_i).to eq(0)

      # Calendrier + veto libérés.
      expect(space.available_on?(from)).to be(true)
      expect(room.reservations.count).to eq(0)

      # Trace financière conservée.
      expect(Payment.find_by(id: payment.id)).to be_present
    end

    it "gère un séjour hébergement-seul (pas de SpaceBooking)" do
      from = Date.today + 500
      booking = Booking.create!(firstname: "Solo", group_name: "G", lodging: lodging,
                                from_date: from, to_date: from + 1, adults: 1, children: 0, babies: 0,
                                status: "confirmed", booking_type: "lodging", price_cents: 0)
      Reservation.create!(booking: booking, room: room, date: from)
      stay = Stays::EnsureForBooking.call(booking)

      described_class.new(stay: stay).run

      expect(Stay.find_by(id: stay.id)).to be_nil
      expect(Booking.find_by(id: booking.id)).to be_nil
      expect(Reservation.where(booking_id: booking.id).count).to eq(0)
    end
  end
end
