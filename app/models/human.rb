# == Schema Information
#
# Table name: humans
#
#  id          :bigint           not null, primary key
#  name        :string
#  email       :string
#  photo       :string
#  summary     :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  status      :string           default("active")
#
class Human < ApplicationRecord
  has_many :projects
  has_many :experiences
  has_many :services

  has_one :user

  has_and_belongs_to_many :tasks

  self.table_name = "humans"

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  mount_uploader :photo, HumanAvatarUploader

  default_scope -> { where(status: "active").order(:name) }

	validates :name,
            presence: true,
            uniqueness: true

  def inactive?
    self.status == "inactive"
  end
end
