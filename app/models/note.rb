class Note < ApplicationRecord
  has_paper_trail
  
  validates :body, presence: true
  validates :date, presence: true 
end
