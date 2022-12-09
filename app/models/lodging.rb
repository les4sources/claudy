class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms
  has_many :bookings

  monetize :price_night_cents
  monetize :price_weekend_cents

  def available_on?(date)
    # none of the lodging rooms has a confirmed reservation
    Reservation
      .includes(:booking)
      .where(
        date: date,
        room: rooms.pluck(:id),
        booking: { status: "confirmed" }
      ).none?
  end

  def form_label
    "#{name} (#{summary})"
  end
end
