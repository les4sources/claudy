# == Schema Information
#
# Table name: watchman_notes
#
#  id         :bigint           not null, primary key
#  date       :date
#  note       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_watchman_notes_on_date  (date)
#
class WatchmanNote < ApplicationRecord
  validates :date, presence: true
  validates :note, presence: true
  
  scope :for_date, ->(date) { where(date: date) }
end
