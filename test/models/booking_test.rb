# == Schema Information
#
# Table name: bookings
#
#  id                 :bigint           not null, primary key
#  firstname          :string
#  lastname           :string
#  phone              :string
#  email              :string
#  from_date          :date
#  to_date            :date
#  status             :string
#  adults             :integer
#  children           :integer
#  payment_status     :string
#  payment_method     :string
#  bedsheets          :boolean
#  towels             :boolean
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  price_cents        :integer
#  invoice_status     :string
#  contract_status    :string
#  estimated_arrival  :string
#  option_babysitting :boolean
#  option_partyhall   :boolean
#  option_bread       :boolean
#  comments           :text
#  tier               :string
#  lodging_id         :bigint
#  option_discgolf    :boolean
#  shown_price_cents  :integer          default(0), not null
#  token              :string
#  platform           :string
#  group_name         :string
#  babies             :integer          default(0)
#  public_notes       :text
#  departure_time     :string
#  option_pizza_party :boolean
#  deleted_at         :datetime
#  wifi               :boolean          default(FALSE)
#
require "test_helper"

class BookingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
