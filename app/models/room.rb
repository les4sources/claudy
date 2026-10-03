# == Schema Information
#
# Table name: rooms
#
#  id          :bigint           not null, primary key
#  code        :string
#  deleted_at  :datetime
#  description :text
#  level       :integer
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Room < ApplicationRecord
  has_many :reservations
  has_many :lodging_rooms
  has_many :lodgings, through: :lodging_rooms

  has_soft_deletion default_scope: true

  # La mezzanine de la Hulotte (code MEZ, « Laurier (mezzanine) ») porte deux
  # lits mais ne compte pas comme une chambre pour le client (Michael,
  # 2026-10-03) : la Hulotte s'annonce 5 chambres, le Grand-Duc 7.
  def mezzanine?
    code.to_s.casecmp?("MEZ") || name.to_s.match?(/mezzanine/i)
  end

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
