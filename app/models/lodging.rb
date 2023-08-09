# == Schema Information
#
# Table name: lodgings
#
#  id                      :integer          not null, primary key
#  name                    :string
#  description             :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  summary                 :string
#  price_night_cents       :integer          default(0), not null
#  party_hall_availability :boolean
#  weekend_discount_cents  :integer          default(0), not null
#  deleted_at              :datetime
#
class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms
  has_many :bookings

  monetize :price_night_cents

  has_soft_deletion default_scope: true

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
