# == Schema Information
#
# Table name: teams
#
#  id          :integer          not null, primary key
#  name        :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Team < ApplicationRecord
  has_many :bundles
  has_many :tasks, through: :bundles
  
  has_paper_trail
  has_soft_deletion default_scope: true
  
  has_rich_text :description
  
  validates :name,
            presence: true,
            uniqueness: true
end
