class CycleAction < ApplicationRecord
  belongs_to :human
  belongs_to :delegate_to_human, class_name: "Human", optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  enum category: {
    rituelle: 0,
    ponctuelle: 1,
    reportee: 2,
    deleguee: 3,
    demandee: 4,
    invitee: 5
  }

  validates :label, presence: true
  validates :category, presence: true

  scope :active, -> { where(completed: false) }
  scope :for_human, ->(human) { where(human: human) }
  scope :ordered, -> { order(:completed, :position, :created_at) }

  before_create :set_default_position

  private

  def set_default_position
    return if position.to_i > 0
    max = CycleAction.where(human_id: human_id, category: category).maximum(:position) || -1
    self.position = max + 1
  end
end
