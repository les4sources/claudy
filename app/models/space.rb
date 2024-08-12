# == Schema Information
#
# Table name: spaces
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  code        :string
#  deleted_at  :datetime
#  position    :integer          default(999)
#
class Space < ApplicationRecord
  has_many :space_reservations

  #v2 - stays
  has_many :stay_items, as: :bookable

  has_soft_deletion default_scope: true

  default_scope -> { order(:position) }

  def booked_on?(date)
    SpaceReservation.includes(:space_booking)
                    .where(
                      date: date,
                      space: self.id,
                      space_booking: { status: "confirmed" }
                    ).exists?
  end
end
