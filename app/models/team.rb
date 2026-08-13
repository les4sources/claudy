# == Schema Information
#
# Table name: teams
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  name        :string
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
