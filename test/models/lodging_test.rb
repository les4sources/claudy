# == Schema Information
#
# Table name: lodgings
#
#  id                      :bigint           not null, primary key
#  available_for_bookings  :boolean
#  deleted_at              :datetime
#  description             :text
#  name                    :string
#  party_hall_availability :boolean
#  price_night_cents       :integer          default(0), not null
#  show_on_reports         :boolean          default(TRUE)
#  summary                 :string
#  weekend_discount_cents  :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
require "test_helper"

class LodgingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
