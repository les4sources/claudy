# == Schema Information
#
# Table name: events
#
#  id                 :bigint           not null, primary key
#  attendees          :integer
#  deleted_at         :datetime
#  ends_at            :datetime
#  name               :string
#  notes              :text
#  sales_amount_cents :integer
#  starts_at          :datetime
#  status             :string
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_category_id  :bigint           not null
#
# Indexes
#
#  index_events_on_event_category_id  (event_category_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_category_id => event_categories.id)
#
require "test_helper"

class EventTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
