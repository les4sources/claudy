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
require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
