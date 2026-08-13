# == Schema Information
#
# Table name: roles
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime
#  name       :string
#  role_team  :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_roles_on_role_team  (role_team) USING gin
#
class Role < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name,
            presence: true,
            uniqueness: true
end
