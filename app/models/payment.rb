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
class Payment < ApplicationRecord
  # notify ActiveRecord that the default sort order should be created_at
  self.implicit_order_column = :created_at

  belongs_to :booking

  monetize :amount_cents, allow_nil: false

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :amount, numericality: { greater_than: 0.0 }
  validates :payment_method, presence: true

  scope :paid, -> { where(status: "paid") }
  scope :pending, -> { where(status: "pending") }

  def paid?
    self.status == "paid"
  end

  def pending?
    self.status == "pending"
  end
end
