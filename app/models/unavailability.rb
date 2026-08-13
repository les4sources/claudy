# == Schema Information
#
# Table name: unavailabilities
#
#  id         :bigint           not null, primary key
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  lodging_id :bigint           not null
#
# Indexes
#
#  index_unavailabilities_on_lodging_id  (lodging_id)
#
# Foreign Keys
#
#  fk_rails_...  (lodging_id => lodgings.id)
#
class Unavailability < ApplicationRecord
  validates :date,
            presence: true
  belongs_to :lodging
end
