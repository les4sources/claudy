# == Schema Information
#
# Table name: lodging_rooms
#
#  id         :integer          not null, primary key
#  lodging_id :integer          not null
#  room_id    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class LodgingRoom < ApplicationRecord
  belongs_to :lodging
  belongs_to :room
end
