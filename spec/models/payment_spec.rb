# == Schema Information
#
# Table name: payments
#
#  booking_id                 :bigint           not null
#  payment_method             :string
#  status                     :string
#  deleted_at                 :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  amount_cents               :integer          default(0), not null
#  stripe_checkout_session_id :string
#  stripe_payment_intent_id   :string
#  id                         :uuid             not null, primary key
#
require 'rails_helper'

RSpec.describe Payment, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
