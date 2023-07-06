class Note < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :body, presence: true
  validates :date, presence: true 
end
