# == Schema Information
#
# Table name: tasks
#
#  id          :integer          not null, primary key
#  name        :string
#  project_id  :integer          not null
#  description :text
#  status      :string
#  due_date    :date
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Task < ApplicationRecord
  belongs_to :project

  has_and_belongs_to_many :humans

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  STATUS_OPEN = 'open'
  STATUS_IN_PROGRESS = 'in_progress'
  STATUS_CLOSED = 'closed'
  STATUS_CANCELED = 'canceled'

  validates :name,
            presence: true,
            uniqueness: true

  def closed?
    self.status == STATUS_CLOSED
  end
end
