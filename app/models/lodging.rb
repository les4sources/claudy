class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms

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
end
