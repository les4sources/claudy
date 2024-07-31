class StayItem < ApplicationRecord
  
  belongs_to :stay
  belongs_to :bookable, polymorphic: true


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

end