# == Schema Information
#
# Table name: stay_item_dates
#
#  id               :bigint           not null, primary key
#  booked_item_type :string           not null
#  booked_item_id   :bigint           not null
#  booking_date     :date             not null
#  stay_id          :bigint           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  direct_book      :boolean          default(TRUE)
#  stay_item_id     :bigint
#
class StayItemDate < ApplicationRecord
  belongs_to :booked_item, polymorphic: true
  belongs_to :stay
  belongs_to :stay_item

  def start_time
    booking_date.to_time
  end

  def self.build_item_dates(stay_id, stay_item, booked_item_id, booked_item_type, direct_book=false)
    
    (stay_item.start_date..stay_item.end_date).each do |date|
      StayItemDate.create!(stay_id: stay_id, 
                           booked_item_id: booked_item_id, 
                           booked_item_type: booked_item_type,
                           booking_date: date,
                           stay_item_id: stay_item.id,
                           direct_book: direct_book)
    end
  end

end
