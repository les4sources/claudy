# == Schema Information
#
# Table name: tasks
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  due_date    :date
#  name        :string
#  status      :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  bundle_id   :bigint           not null
#  project_id  :bigint           not null
#
# Indexes
#
#  index_tasks_on_bundle_id   (bundle_id)
#  index_tasks_on_project_id  (project_id)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (project_id => projects.id)
#
class Task < ApplicationRecord
  belongs_to :bundle
  belongs_to :project, optional: true
  belongs_to :team, optional: true
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
