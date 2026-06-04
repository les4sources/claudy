class GatheringAction < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :gathering
  has_and_belongs_to_many :assignees,
                          class_name: "Human",
                          join_table: :gathering_action_humans

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :label, presence: true

  scope :ordered, -> { order(:completed, :position, :id) }
  scope :active, -> { where(completed: false) }

  before_create :assign_next_position

  def done?
    completed?
  end

  # Flips the shared completed state. One checkbox per action: ticking it from
  # the member dashboard or from the gathering page mutates the same record.
  def toggle_completed!
    update!(completed: !completed, completed_at: completed? ? nil : Time.current)
  end

  private

  def assign_next_position
    return if position.present? && position.positive?
    max = gathering.gathering_actions.maximum(:position) || -1
    self.position = max + 1
  end
end
