class Bed < ApplicationRecord

  belongs_to :room
  has_many :stay_items, as: :bookable, dependent: :destroy

  validates :name, presence: true


  default_scope { order(name: :asc) }


  def name_with_room
  	"#{self.name} (#{self.room.name})"
  end


end
