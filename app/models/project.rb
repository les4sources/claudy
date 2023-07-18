class Project < ApplicationRecord
  belongs_to :human, optional: true
  has_many :tasks


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
