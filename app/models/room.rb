class Room < ApplicationRecord
  has_many :lodging_rooms
  has_many :lodgings, through: :lodging_rooms
end
