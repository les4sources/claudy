class StayItem < ApplicationRecord
  
  belongs_to :stay
  belongs_to :item, polymorphic: true
  has_many :payment_requests_stay_items
  has_many :payment_requests, through: :payment_requests_stay_items


  ROOM = 'Room'
  BED = 'Bed'
  SPACE = 'Space'
  EXPERIENCE = 'Experience'
  PRODUCT = 'Product'
  RENTAL_ITEM = 'RentalItem'


  def self.build
    
    items = []

    Lodging.all.each do |lod|
      obj = {id: lod.id, type: 'Lodging', name: lod.name}
      items << obj
    end 
    Room.all.each do |room|
      obj = {id: room.id, type: 'Room', name: room.name}
      items << obj
    end 
    Bed.all.each do |bed|
      obj = {id: bed.id, type: 'Bed', name: bed.name_with_room}
      items << obj
    end 
    Space.all.each do |space|
      obj = {id: space.id, type: 'Space', name: space.name}
      items << obj
    end 
  
    items
    
  end

  def total_price 
    unit_price_cents * quantity
  end



end