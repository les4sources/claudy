class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms
end
