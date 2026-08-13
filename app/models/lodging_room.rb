# == Schema Information
#
# Table name: lodging_rooms
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  lodging_id :bigint           not null
#  room_id    :bigint           not null
#
# Indexes
#
#  index_lodging_rooms_on_lodging_id  (lodging_id)
#  index_lodging_rooms_on_room_id     (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (lodging_id => lodgings.id)
#  fk_rails_...  (room_id => rooms.id)
#
class LodgingRoom < ApplicationRecord
  belongs_to :lodging
  belongs_to :room
end
