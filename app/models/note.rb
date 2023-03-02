class Note < ApplicationRecord
  validates :body, presence: true
  validates :date, presence: true 
end
