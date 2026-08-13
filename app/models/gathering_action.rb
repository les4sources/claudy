# == Schema Information
#
# Table name: gathering_actions
#
#  id           :bigint           not null, primary key
#  completed    :boolean          default(FALSE), not null
#  completed_at :datetime
#  deleted_at   :datetime
#  label        :string           not null
#  position     :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  gathering_id :bigint           not null
#
# Indexes
#
#  index_gathering_actions_on_deleted_at                 (deleted_at)
#  index_gathering_actions_on_gathering_id               (gathering_id)
#  index_gathering_actions_on_gathering_id_and_position  (gathering_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (gathering_id => gatherings.id)
#
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
