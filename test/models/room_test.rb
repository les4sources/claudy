# == Schema Information
#
# Table name: rooms
#
#  id          :bigint           not null, primary key
#  code        :string
#  deleted_at  :datetime
#  description :text
#  level       :integer
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require "test_helper"

class RoomTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
