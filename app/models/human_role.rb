# == Schema Information
#
# Table name: human_roles
#
#  id         :bigint           not null, primary key
#  human_id   :bigint           not null
#  role_id    :bigint           not null
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class HumanRole < ApplicationRecord
  belongs_to :human
  belongs_to :role

  validates :date, presence: true
end
