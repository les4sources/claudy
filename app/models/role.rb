# == Schema Information
#
# Table name: roles
#
#  id         :bigint           not null, primary key
#  name       :string
#  deleted_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Role < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name,
            presence: true,
            uniqueness: true
end
