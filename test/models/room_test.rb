# == Schema Information
#
# Table name: rooms
#
#  id                :bigint           not null, primary key
#  name              :string
#  description       :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  level             :integer
#  code              :string
#  deleted_at        :datetime
#  price_night_cents :integer          default(0), not null
#
require "test_helper"

class RoomTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
