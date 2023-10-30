# == Schema Information
#
# Table name: space_bookings
#
#  id                   :bigint           not null, primary key
#  firstname            :string
#  lastname             :string
#  group_name           :string
#  phone                :string
#  email                :string
#  from_date            :date
#  to_date              :date
#  status               :string
#  tier                 :string
#  payment_status       :string
#  invoice_status       :string
#  contract_status      :string
#  notes                :text
#  token                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  price_cents          :integer
#  payment_method       :string
#  event_id             :bigint
#  public_notes         :text
#  paid_amount_cents    :integer
#  deposit_amount_cents :integer
#  persons              :string
#  arrival_time         :string
#  departure_time       :string
#  option_kitchenware   :boolean          default(FALSE)
#  option_beamer        :boolean          default(FALSE)
#  option_wifi          :boolean          default(FALSE)
#  option_tables        :boolean          default(FALSE)
#  advance_amount_cents :integer
#  deleted_at           :datetime
#
require 'rails_helper'

RSpec.describe SpaceBooking, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
