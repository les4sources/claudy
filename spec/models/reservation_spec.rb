require "rails_helper"

# == Schema Information
#
# Table name: reservations
#
#  id         :bigint           not null, primary key
#  date       :date
#  deleted_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  booking_id :bigint           not null
#  room_id    :bigint           not null
#
# Indexes
#
#  index_reservations_on_booking_id  (booking_id)
#  index_reservations_on_room_id     (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (booking_id => bookings.id)
#  fk_rails_...  (room_id => rooms.id)
#
RSpec.describe Reservation, type: :model do
  # Regression: the `deleted_at` column existed since migration 20230706080125
  # but `has_soft_deletion` was never declared on Reservation, so a soft-deleted
  # reservation stayed visible and kept blocking availability — producing a false
  # "Cet hébergement n'est pas disponible à cette date." on booking edits
  # (Sentry 7296086238, booking 810).
  describe "soft deletion" do
    let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
    let(:room) { make_room(lodging, "HU") }
    let(:window) { [Date.new(2026, 8, 1), Date.new(2026, 8, 3)] }

    def make_room(lodging, code)
      room = Room.create!(name: "Chambre #{code}", level: 1)
      lodging.rooms << room
      room
    end

    def reserve(room, from:, to:)
      booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed")
      reservations = (from..to).map { |date| Reservation.create!(booking: booking, room: room, date: date) }
      [booking, reservations]
    end

    it "hides soft-deleted reservations from the default scope" do
      _booking, reservations = reserve(room, from: window.first, to: window.last)

      reservations.each(&:soft_delete!)

      expect(Reservation.where(id: reservations.map(&:id))).to be_empty
      expect(Reservation.unscoped.where(id: reservations.map(&:id)).count).to eq(reservations.size)
      expect(room.reservations.reload).to be_empty
    end

    it "does not count a soft-deleted reservation as blocking availability" do
      _booking, reservations = reserve(room, from: window.first, to: window.last)
      reservations.each(&:soft_delete!)

      expect(lodging.self_available_between?(*window)).to be(true)
    end

    it "still blocks availability for a live reservation" do
      reserve(room, from: window.first, to: window.last)

      expect(lodging.self_available_between?(*window)).to be(false)
    end
  end
end
