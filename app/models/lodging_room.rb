# == Schema Information
#
# Table name: lodging_rooms
#
#  id         :bigint           not null, primary key
#  lodging_id :bigint           not null
#  room_id    :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class LodgingRoom < ApplicationRecord
  belongs_to :lodging
  belongs_to :room
end
