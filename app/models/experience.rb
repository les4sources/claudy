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
#  duration_hours    :decimal(, )
#
class Experience < ApplicationRecord
  belongs_to :human, optional: true

  has_many :experience_availabilities, dependent: :destroy
  has_many :experience_bookings, through: :experience_availabilities

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true
  monetize :fixed_price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :name,
            presence: true,
            uniqueness: true
  validates :duration_hours,
            numericality: { greater_than: 0 },
            allow_nil: true

  # Durée d'un bloc de disponibilité, en minutes, dérivée de la durée numérique
  # en heures. Pilote la taille des créneaux (Phase 4 de l'épic #25). Renvoie
  # nil tant qu'aucune durée numérique n'a été renseignée.
  def block_duration_minutes
    return nil if duration_hours.nil?

    (duration_hours * 60).round
  end
end
