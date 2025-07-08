# == Schema Information
#
# Table name: rooms
#
#  id                :bigint           not null, primary key
#  name              :string
#  description       :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  level             :integer
#  code              :string
#  deleted_at        :datetime
#  price_night_cents :integer          default(0), not null
#
class Room < ApplicationRecord
  has_many :reservations
  has_many :lodging_rooms
  has_many :lodgings, through: :lodging_rooms
  has_many :beds, dependent: :destroy

  # v2 - stays
  has_many :stay_items, as: :item
  has_many :stays, through: :stay_items
  has_many :stay_item_dates, as: :booked_item

  has_soft_deletion default_scope: true

  default_scope { order(name: :asc) }



 # price constant
 # night_count => price
 # currently same price for each room, add the room_id as an up hash key should rooms had different prices
  PRICES = {
      1 => 12000,
      2 => 24000,
      3 => 36000,
      4 => 48000,
      5 => 60000,
      6 => 72000
  }.freeze
  
   def price(nights_count)
      PRICES[nights_count] if nights_count
   end



  def name_with_level
    case level
    when 0
      "#{name} (rez-de-chaussée)"
    when 1
      "#{name} (1er étage)"
    when 2
      "#{name} (2ème étage)"
    end
  end

  def form_label
    "#{name} (#{description})"
  end

  def available?(start_date, end_date)
    # check if the room is available
    return false if StayItemDate.where(item_booked: self, booking_date: start_date..end_date).exists?

    # check if the corresponding lodgings are available
    self.lodgings.each do |lod|
      return false if StayItemDate.where(item_booked: lod, booking_date: start_date..end_date).exists?
    end

    true
  end

end
