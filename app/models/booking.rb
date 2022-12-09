class Booking < ApplicationRecord
  has_many :reservations, dependent: :destroy
  has_many :rooms, through: :reservations
  belongs_to :lodging

  monetize :price_cents, allow_nil: true

  default_scope -> { order(from_date: :desc) }

  attr_accessor :invoice_wanted
  attr_accessor :room_ids
  attr_accessor :booking_type # lodging || rooms

  validates :firstname,       presence: true
  validates :lastname,        presence: true
  validates :email,           presence: true
  validates :from_date,       presence: true
  validates :to_date,         presence: true
  validates :adults,          presence: true
  validates :children,        presence: true
  validates :payment_method,  presence: true
  # validates :lodging_id,  presence: true

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
  end

  def name
    "#{firstname} #{lastname}"
  end

  def pending?
    status == "pending"
  end
end
