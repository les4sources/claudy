# == Schema Information
#
# Table name: projects
#
#  id          :integer          not null, primary key
#  name        :string
#  description :text
#  due_date    :date
#  human_id    :integer          not null
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Project < ApplicationRecord
  belongs_to :human, optional: true
  has_many :bundles
  has_many :tasks, through: :bundles

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  validates :name,
            presence: true,
            uniqueness: true

  def tasks_canceled
    tasks.where(status: Task::STATUS_CANCELED)
  end

  def tasks_closed
    tasks.where(status: Task::STATUS_CLOSED)
  end

  def tasks_in_progress
    tasks.where(status: Task::STATUS_IN_PROGRESS)
  end

  def tasks_open
    tasks.where(status: Task::STATUS_OPEN)
  end
end
