# == Schema Information
#
# Table name: beds
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  price_cents :integer
#  room_id     :bigint
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Bed < ApplicationRecord

  belongs_to :room
  # v2 - stays
  has_many :stay_items, as: :item
  has_many :stays, through: :stay_items

  validates :name, presence: true


  default_scope { order(name: :asc) }


  def name_with_room
  	"#{self.name} (#{self.room.name})"
  end

  def form_label
    "#{name} (#{description}) - chambre #{self.room.name} "
  end


end
