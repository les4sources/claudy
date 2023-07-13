class Human < ApplicationRecord
  self.table_name = "humans"

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  mount_uploader :photo, HumanAvatarUploader

	validates :name,
            presence: true,
            uniqueness: true
end
