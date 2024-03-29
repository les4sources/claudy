# == Schema Information
#
# Table name: space_reservations
#
#  id               :bigint           not null, primary key
#  space_booking_id :bigint           not null
#  space_id         :bigint           not null
#  date             :date
#  duration         :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  deleted_at       :datetime
#
class SpaceReservation < ApplicationRecord
  belongs_to :space_booking
  belongs_to :space

  has_paper_trail

  def start_time
    date.to_time
  end
end
