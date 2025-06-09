# == Schema Information
#
# Table name: rooms
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  level       :integer
#  code        :string
#  deleted_at  :datetime
#
class Room < ApplicationRecord
  has_many :reservations
  has_many :lodging_rooms
  has_many :lodgings, through: :lodging_rooms

  has_soft_deletion default_scope: true

  def name_with_level
    case level
    when -1
      "#{name} (extérieur)"
    when 0
      "#{name} (rez-de-chaussée)"
    when 1
      "#{name} (1er étage)"
    when 2
      "#{name} (2ème étage)"
    end
  end
end
