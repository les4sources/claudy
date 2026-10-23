# == Schema Information
#
# Table name: services
#
#  id                 :bigint           not null, primary key
#  deleted_at         :datetime
#  description        :text
#  name               :string
#  photo              :string
#  price_cents        :integer
#  summary            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint
#  human_id           :bigint
#
# Indexes
#
#  index_services_on_general_account_id  (general_account_id)
#  index_services_on_human_id            (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (human_id => humans.id)
#
class Service < ApplicationRecord
  belongs_to :human, optional: true
  # Compte de recette des lignes de séjour reprises de ce service (Michael,
  # 2026-10-23) : 700006 pour le disc-golf. Facultatif.
  belongs_to :general_account, optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :name,
            presence: true,
            uniqueness: true

  scope :ordered, -> { order(:name) }
end
