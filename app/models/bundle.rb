class Bundle < ApplicationRecord
  belongs_to :project, optional: true
  belongs_to :team, optional: true
  has_many :tasks

  has_paper_trail
  has_soft_deletion default_scope: true
end
