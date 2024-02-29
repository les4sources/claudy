# == Schema Information
#
# Table name: payments
#
#  id             :bigint           not null, primary key
#  booking_id     :bigint           not null
#  payment_method :string
#  status         :string
#  deleted_at     :datetime
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  amount_cents   :integer          default(0), not null
#
class Payment < ApplicationRecord
  belongs_to :booking

  monetize :amount_cents, allow_nil: false

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :amount, numericality: { greater_than: 0.0 }
  validates :payment_method, presence: true
end
