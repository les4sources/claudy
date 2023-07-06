class Product < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true

  validates :name,
            presence: true,
            uniqueness: true
end
