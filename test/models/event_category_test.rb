# == Schema Information
#
# Table name: event_categories
#
#  id         :bigint           not null, primary key
#  name       :string
#  color      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  deleted_at :datetime
#
require "test_helper"

class EventCategoryTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
