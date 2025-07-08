# == Schema Information
#
# Table name: stay_items
#
#  id                     :bigint           not null, primary key
#  stay_id                :bigint           not null
#  item_type              :string           not null
#  item_id                :bigint           not null
#  start_date             :date             not null
#  end_date               :date             not null
#  quantity               :integer          default(1)
#  adults_count           :integer
#  children_count         :integer
#  duration               :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  unit_price_cents       :integer          default(0), not null
#  unit_price_currency    :string           default("EUR"), not null
#  babies_count           :integer
#  calculated_price_cents :integer          default(0), not null
#
class StayItem < ApplicationRecord
  belongs_to :stay
  belongs_to :item, polymorphic: true
  has_many :stay_item_dates

  LODGING = 'Lodging'
  ROOM = 'Room'
  BED = 'Bed'
  SPACE = 'Space'
  EXPERIENCE = 'Experience'
  PRODUCT = 'Product'
  RENTAL_ITEM = 'RentalItem'

  ITEM_TYPE_ORDER = [SPACE, LODGING, ROOM, BED, EXPERIENCE, PRODUCT, RENTAL_ITEM]

  scope :order_by_item_type, -> {
    order(
      Arel.sql(
        "CASE item_type " +
        ITEM_TYPE_ORDER.map.with_index { |type, index| "WHEN '#{type}' THEN #{index}" }.join(" ") +
        " END"
      ),
    )
  }

  monetize :calculated_price_cents, as: "calculated_price"

  def total_price
    unit_price_cents * quantity
  end

  def nights_count
    (self.end_date - self.start_date).to_i
  end
end
