# == Schema Information
#
# Table name: lodging_compositions
#
#  id                  :bigint           not null, primary key
#  composite_lodging_id :bigint          not null
#  component_lodging_id :bigint          not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class LodgingComposition < ApplicationRecord
  belongs_to :composite_lodging, class_name: "Lodging"
  belongs_to :component_lodging, class_name: "Lodging"

  validates :component_lodging_id, uniqueness: { scope: :composite_lodging_id }
  validate :no_self_composition

  private

  def no_self_composition
    if composite_lodging_id == component_lodging_id
      errors.add(:component_lodging_id, "ne peut pas être le composite lui-même")
    end
  end
end
