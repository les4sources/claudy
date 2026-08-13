# == Schema Information
#
# Table name: services
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  name        :string
#  photo       :string
#  price_cents :integer
#  summary     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  human_id    :bigint
#
# Indexes
#
#  index_services_on_human_id  (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
class Service < ApplicationRecord
  belongs_to :human, optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :name,
            presence: true,
            uniqueness: true
end
