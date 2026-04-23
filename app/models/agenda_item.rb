# == Schema Information
#
# Table name: agenda_items
#
#  id           :bigint           not null, primary key
#  gathering_id :bigint           not null
#  author_id    :bigint           not null
#  title        :string           not null
#  position     :integer          default(0), not null
#  completed    :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  deleted_at   :datetime
#
class AgendaItem < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :gathering
  belongs_to :author, class_name: "Human"
  has_many :decisions, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  validates :title, presence: true

  scope :ordered, -> { order(position: :asc, id: :asc) }
  scope :pending, -> { where(completed: false) }

  before_create :assign_next_position

  private

  def assign_next_position
    return if position.present? && position.positive?
    max = gathering.agenda_items.maximum(:position) || -1
    self.position = max + 1
  end
end
