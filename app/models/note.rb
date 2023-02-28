class Note < ApplicationRecord
  validates :body, presence: true
end
