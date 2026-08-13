# == Schema Information
#
# Table name: space_bookings
#
#  id                   :bigint           not null, primary key
#  advance_amount_cents :integer
#  arrival_time         :string
#  contract_status      :string
#  deleted_at           :datetime
#  departure_time       :string
#  deposit_amount_cents :integer
#  email                :string
#  firstname            :string
#  from_date            :date
#  group_name           :string
#  invoice_status       :string
#  lastname             :string
#  notes                :text
#  option_beamer        :boolean          default(FALSE)
#  option_kitchenware   :boolean          default(FALSE)
#  option_tables        :boolean          default(FALSE)
#  option_wifi          :boolean          default(FALSE)
#  paid_amount_cents    :integer
#  payment_method       :string
#  payment_status       :string
#  persons              :string
#  phone                :string
#  price_cents          :integer
#  public_notes         :text
#  status               :string
#  tier                 :string
#  to_date              :date
#  token                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  event_id             :bigint
#
# Indexes
#
#  index_space_bookings_on_event_id  (event_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
require 'rails_helper'

RSpec.describe SpaceBooking, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
