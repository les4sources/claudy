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



 # price constant
  PRICES = {
    1 => {
      "2h" => 11000,
      "day" => 25000,
      "evening" => 25000,
      "fullday" => 38000,
      "see_notes" => 0
    },
    2 => {
      "2h" => 5500,
      "day" => 12000,
      "evening" => 12000,
      "fullday" => 19000,
      "see_notes" => 0
    },
    3 => {
      "2h" => 14500,
      "day" => 33500,
      "evening" => 33500,
      "fullday" => 49500,
      "see_notes" => 0
    },
    4 => {
      "2h" => 4500,
      "day" => 9500,
      "evening" => 9500,
      "fullday" => 15000,
      "see_notes" => 0
    },
    5 => {
      "2h" => 0,
      "day" => 0,
      "evening" => 0,
      "fullday" => 0,
      "see_notes" => 0
    },
    6 => {
      "2h" => 0,
      "day" => 0,
      "evening" => 0,
      "fullday" => 0,
      "see_notes" => 0
    }
  }.freeze


 def price(duration)
    PRICES[id][duration] if PRICES[id]
 end


  def booked_on?(date)
    SpaceReservation.includes(:space_booking)
                    .where(
                      date: date,
                      space: self.id,
                      space_booking: { status: "confirmed" }
                    ).exists?
  end
end
