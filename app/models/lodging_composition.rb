# == Schema Information
#
# Table name: lodging_compositions
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  component_lodging_id :bigint           not null
#  composite_lodging_id :bigint           not null
#
# Indexes
#
#  index_lodging_compositions_on_component_lodging_id  (component_lodging_id)
#  index_lodging_compositions_on_composite_lodging_id  (composite_lodging_id)
#  index_lodging_compositions_unique_pair              (composite_lodging_id,component_lodging_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (component_lodging_id => lodgings.id)
#  fk_rails_...  (composite_lodging_id => lodgings.id)
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
