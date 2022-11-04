class Booking < ApplicationRecord
  has_many :reservations, dependent: :destroy
  has_many :rooms, through: :reservations

  monetize :price_cents, allow_nil: true

  default_scope -> { order(from_date: :desc) }

  attr_accessor :room_ids

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
  end

  def pending?
    status == "pending"
  end
end
