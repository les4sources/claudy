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
require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
