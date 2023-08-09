# == Schema Information
#
# Table name: events
#
#  id                :integer          not null, primary key
#  name              :string
#  event_category_id :integer          not null
#  starts_at         :datetime
#  ends_at           :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  deleted_at        :datetime
#  url               :string
#
require "test_helper"

class EventTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
