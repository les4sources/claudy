class StayItemDate < ApplicationRecord
  belongs_to :booked_item, polymorphic: true
  belongs_to :stay
  belongs_to :stay_item

  def start_time
    booking_date.to_time
  end


  def self.build_item_dates(stay_id, stay_item, item_type, direct_book=false)
    (start_date..end_date).each do |date|
      StayItemDate.create!(stay_id: stay_id, 
                           booked_item_id: stay_item.item_id, 
                           booked_item_type: stay_item.item_type,
                           booking_date: stay_item.start_date,
                           stay_item_id: stay_item.id,
                           direct_book: direct_book)
    end
  end

end