# == Schema Information
#
# Table name: lodgings
#
#  id                      :integer          not null, primary key
#  name                    :string
#  description             :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  summary                 :string
#  price_night_cents       :integer          default(0), not null
#  party_hall_availability :boolean
#  weekend_discount_cents  :integer          default(0), not null
#  deleted_at              :datetime
#
require "test_helper"

class LodgingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
