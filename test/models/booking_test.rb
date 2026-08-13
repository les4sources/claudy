# == Schema Information
#
# Table name: bookings
#
#  id                 :bigint           not null, primary key
#  adults             :integer
#  babies             :integer          default(0)
#  bedsheets          :boolean
#  booking_type       :string
#  children           :integer
#  comments           :text
#  contract_status    :string
#  deleted_at         :datetime
#  departure_time     :string
#  email              :string
#  estimated_arrival  :string
#  firstname          :string
#  from_date          :date
#  group_name         :string
#  invoice_status     :string
#  lastname           :string
#  notes              :text
#  option_babysitting :boolean
#  option_bread       :boolean
#  option_discgolf    :boolean
#  option_partyhall   :boolean
#  option_pizza_party :boolean
#  payment_method     :string
#  payment_status     :string
#  phone              :string
#  platform           :string
#  price_cents        :integer
#  public_notes       :text
#  shown_price_cents  :integer          default(0), not null
#  status             :string
#  tier               :string
#  to_date            :date
#  token              :string
#  towels             :boolean
#  wifi               :boolean          default(FALSE)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  lodging_id         :bigint
#
# Indexes
#
#  index_bookings_on_lodging_id  (lodging_id)
#
# Foreign Keys
#
#  fk_rails_...  (lodging_id => lodgings.id)
#
require "test_helper"

class BookingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
