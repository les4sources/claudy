# == Schema Information
#
# Table name: stay_items
#
#  id             :bigint           not null, primary key
#  stay_id        :bigint           not null
#  item_type      :string           not null
#  item_id        :bigint           not null
#  start_date     :date             not null
#  end_date       :date             not null
#  quantity       :integer          default(1)
#  unit_price     :decimal(10, 2)
#  adults_count   :integer
#  children_count :integer
#  duration       :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class StayItem < ApplicationRecord
  
  belongs_to :stay
  belongs_to :item, polymorphic: true
  has_many :payment_requests_stay_items
  has_many :payment_requests, through: :payment_requests_stay_items

  LODGING = 'Lodging'
  ROOM = 'Room'
  BED = 'Bed'
  SPACE = 'Space'
  EXPERIENCE = 'Experience'
  PRODUCT = 'Product'
  RENTAL_ITEM = 'RentalItem'

  monetize :calculated_price_cents,as: "calculated_price"


  def total_price 
    unit_price_cents * quantity
  end

  def nights_count
    (self.end_date - self.start_date).to_i
  end



end
