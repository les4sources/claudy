# == Schema Information
#
# Table name: notes
#
#  id         :bigint           not null, primary key
#  body       :text
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  deleted_at :datetime
#  color      :string
#
class Note < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :body, presence: true
  validates :date, presence: true 
end
