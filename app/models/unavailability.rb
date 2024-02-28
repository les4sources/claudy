# == Schema Information
#
# Table name: unavailabilities
#
#  id         :bigint           not null, primary key
#  date       :date
#  lodging_id :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Unavailability < ApplicationRecord
  validates :date,
            presence: true
  belongs_to :lodging
end
