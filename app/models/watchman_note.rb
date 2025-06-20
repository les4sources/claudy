class WatchmanNote < ApplicationRecord
  validates :date, presence: true
  validates :note, presence: true
  
  scope :for_date, ->(date) { where(date: date) }
end
