# == Schema Information
#
# Table name: reservations
#
#  id         :bigint           not null, primary key
#  booking_id :bigint           not null
#  room_id    :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  date       :date
#  deleted_at :datetime
#
class Reservation < ApplicationRecord
  belongs_to :booking
  belongs_to :room

  has_paper_trail

  def start_time
    date.to_time
  end
end
