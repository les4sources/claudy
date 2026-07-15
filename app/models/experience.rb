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
  # Couleurs du calendrier global des activités (epic #25, Phase 5). Palette fixe
  # et lisible plutôt qu'un vrai hasard : les créneaux de deux activités qui se
  # chevauchent doivent rester distinguables au premier coup d'œil.
  PALETTE = %w[
    #059669 #2563eb #d97706 #7c3aed #db2777 #0891b2
    #65a30d #dc2626 #4f46e5 #ea580c #0d9488 #9333ea
  ].freeze

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
  validates :color,
            format: { with: /\A#[0-9a-f]{6}\z/i },
            allow_nil: true

  before_validation :assign_color, on: :create

  # Durée d'un bloc de disponibilité, en minutes, dérivée de la durée numérique
  # en heures. Pilote la taille des créneaux (Phase 4 de l'épic #25). Renvoie
  # nil tant qu'aucune durée numérique n'a été renseignée.
  def block_duration_minutes
    return nil if duration_hours.nil?

    (duration_hours * 60).round
  end

  private

  # Couleur attribuée à la création : on prend la couleur la moins utilisée de la
  # palette (à égalité, la première dans l'ordre de la palette). Résultat agréable
  # ET stable — deux activités créées à la suite ne peuvent pas se retrouver de la
  # même couleur tant que la palette n'est pas épuisée.
  def assign_color
    return if color.present?

    used = Experience.unscoped.where.not(color: nil).group(:color).count
    self.color = PALETTE.min_by { |candidate| used.fetch(candidate, 0) }
  end
end
