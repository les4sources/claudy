# Une intention d'un membre pour un cycle (epic #330, phase 3).
#
# Les actions d'un cycle disent ce qu'on FAIT ; la target dit ce qu'on VISE.
# Les deux ne se confondent pas : une target peut être atteinte par plusieurs
# actions, ou par aucune.
#
# Une target ne se recopie PAS d'un cycle au suivant (hors périmètre de l'epic
# #330) : une intention se reformule, elle ne se traîne pas.
# == Schema Information
#
# Table name: cycle_targets
#
#  id          :bigint           not null, primary key
#  achieved_at :datetime
#  label       :string           not null
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  cycle_id    :bigint           not null
#  human_id    :bigint           not null
#
# Indexes
#
#  index_cycle_targets_on_cycle_id                            (cycle_id)
#  index_cycle_targets_on_human_id                            (human_id)
#  index_cycle_targets_on_human_id_and_cycle_id_and_position  (human_id,cycle_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (cycle_id => cycles.id)
#  fk_rails_...  (human_id => humans.id)
#
class CycleTarget < ApplicationRecord
  has_paper_trail

  belongs_to :human
  belongs_to :cycle

  validates :label, presence: true
  validates :position, numericality: { only_integer: true }

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :created_at) }
  scope :achieved, -> { where.not(achieved_at: nil) }
  scope :for_cycle, ->(cycle) { where(cycle_id: cycle) }

  def achieved? = achieved_at.present?

  # Atteindre et « désatteindre » sont le même geste, dans les deux sens : une
  # case cochée par erreur doit pouvoir se décocher sans détour.
  def toggle_achieved!
    update!(achieved_at: achieved? ? nil : Time.current)
  end

  private

  # En fin de liste, pour ce membre et ce cycle : une target ajoutée arrive
  # sous les précédentes, là où l'œil l'attend.
  def assign_position
    return if position.present? && position.positive?

    self.position = (self.class.where(human_id: human_id, cycle_id: cycle_id).maximum(:position) || 0) + 1
  end
end
