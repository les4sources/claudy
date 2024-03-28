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
class Paylink < ApplicationRecord
  # notify ActiveRecord that the default sort order should be created_at
  self.implicit_order_column = :created_at

  belongs_to :booking
end
