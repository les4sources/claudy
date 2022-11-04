class Room < ApplicationRecord
  has_many :reservations
  has_many :lodging_rooms
  has_many :lodgings, through: :lodging_rooms

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
end
