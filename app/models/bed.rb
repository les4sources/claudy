# == Schema Information
#
# Table name: beds
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  price_cents :integer
#  room_id     :bigint
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Bed < ApplicationRecord

  belongs_to :room
  # v2 - stays
  has_many :stay_items, as: :item
  has_many :stays, through: :stay_items
  has_many :stay_item_dates, as: :booked_item

  validates :name, presence: true


  default_scope { order(name: :asc) }


# price constant
 # night_count => price
 # currently same price for each room, add the bed_id as an up hash key should beds had different prices
  PRICES = {
      1 => 3500,
      2 => 7000,
      3 => 10500,
      4 => 14000,
      5 => 17500,
      6 => 21000
  }.freeze
  
   def price(nights_count)
      PRICES[nights_count] if nights_count
   end


  def name_with_room
  	"#{self.name} (#{self.room.name})"
  end

  def form_label
    "#{name} (#{description}) - chambre #{self.room.name} "
  end


end
