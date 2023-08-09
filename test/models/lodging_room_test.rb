# == Schema Information
#
# Table name: lodging_rooms
#
#  id         :integer          not null, primary key
#  lodging_id :integer          not null
#  room_id    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
require "test_helper"

class LodgingRoomTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
