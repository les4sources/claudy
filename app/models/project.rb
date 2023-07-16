class Project < ApplicationRecord
  belongs_to :human

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  validates :name,
            presence: true,
            uniqueness: true
end
