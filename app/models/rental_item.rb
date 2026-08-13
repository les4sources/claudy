# == Schema Information
#
# Table name: rental_items
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  name        :string
#  photo       :string
#  price_cents :integer
#  stock       :integer
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
