class StayItemDate < ApplicationRecord
  belongs_to :booked_item, polymorphic: true
  belongs_to :stay


  def start_time
    booking_date.to_time
  end


  def self.build_item_dates(stay_id, item_id, item_type, start_date, end_date, direct_book=false)
    (start_date..end_date).each do |date|
      StayItemDate.create!(stay_id: stay_id, 
                           booked_item_id: item_id, 
                           booked_item_type: item_type,
                           booking_date: date,
                           direct_book: direct_book)
    end
  end

end