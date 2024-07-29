# == Schema Information
#
# Table name: products
#
#  id          :bigint           not null, primary key
#  name        :string
#  stock       :integer
#  photo       :string
#  description :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  price_cents :integer
#
class Product < ApplicationRecord

  #v2 - stays
  has_many :stay_items, as: :bookable

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true

  validates :name,
            presence: true,
            uniqueness: true
end
