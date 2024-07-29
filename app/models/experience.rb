# == Schema Information
#
# Table name: experiences
#
#  id                :bigint           not null, primary key
#  name              :string
#  human_id          :bigint
#  summary           :string
#  description       :text
#  photo             :string
#  deleted_at        :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  price_cents       :integer
#  fixed_price_cents :integer          default(0)
#  min_participants  :integer
#  max_participants  :integer
#  duration          :string
#
class Experience < ApplicationRecord
  belongs_to :human, optional: true

  # v2 - stays
  has_many :stay_items, as: :bookable

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true
  monetize :fixed_price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :name,
            presence: true,
            uniqueness: true
end
