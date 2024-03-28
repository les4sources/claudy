# == Schema Information
#
# Table name: paylinks
#
#  id           :bigint           not null, primary key
#  booking_id   :bigint           not null
#  status       :string
#  checkout_url :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  amount_cents :integer          default(0), not null
#
require 'rails_helper'

RSpec.describe Paylink, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
