# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  name       :string
#  position   :integer
#  project_id :bigint
#  team_id    :bigint
#  deleted_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Bundle < ApplicationRecord
  belongs_to :project, optional: true
  belongs_to :team, optional: true
  has_many :tasks

  has_paper_trail
  has_soft_deletion default_scope: true
end
