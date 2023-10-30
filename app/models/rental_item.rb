# == Schema Information
#
# Table name: rental_items
#
#  id          :bigint           not null, primary key
#  name        :string
#  stock       :integer
#  photo       :string
#  description :text
#  deleted_at  :datetime
#  price_cents :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class RentalItem < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :name,
            presence: true,
            uniqueness: true
end
