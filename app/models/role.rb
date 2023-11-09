class Role < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name,
            presence: true,
            uniqueness: true
end
