# == Schema Information
#
# Table name: experiences
#
#  id                :bigint           not null, primary key
#  color             :string
#  deleted_at        :datetime
#  description       :text
#  duration          :string
#  duration_hours    :decimal(4, 2)
#  fixed_price_cents :integer          default(0)
#  max_participants  :integer
#  min_participants  :integer
#  name              :string
#  photo             :string
#  price_cents       :integer
#  published_at      :datetime
#  slug              :string
#  summary           :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  human_id          :bigint
#
# Indexes
#
#  index_experiences_on_human_id  (human_id)
#  index_experiences_on_slug      (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
class Experience < ApplicationRecord
  # Couleurs du calendrier global des activités (epic #25, Phase 5). Palette fixe
  # et lisible plutôt qu'un vrai hasard : les créneaux de deux activités qui se
  # chevauchent doivent rester distinguables au premier coup d'œil.
  PALETTE = %w[
    #059669 #2563eb #d97706 #7c3aed #db2777 #0891b2
    #65a30d #dc2626 #4f46e5 #ea580c #0d9488 #9333ea
  ].freeze

  # Publication sur le site les4sources.be (catalogue) : `published_at`,
  # `slug`, rebuild.
  include Publishable

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

  # Durée affichée au public : le libellé libre s'il existe, sinon la durée
  # numérique formatée (« 2 h », « 2,5 h »).
  def public_duration_text
    return duration if duration.present?
    return nil if duration_hours.nil?

    formatted = duration_hours.to_d.to_s("F").sub(/\.0+\z/, "").tr(".", ",")
    "#{formatted} h"
  end

  # Dimensions [largeur, hauteur] de la photo originale (CarrierWave, sur le
  # disque), ou nil quand le fichier manque ou qu'ImageMagick ne le lit pas.
  def photo_dimensions
    return nil unless photo? && photo.path.present? && File.exist?(photo.path)

    MiniMagick::Image.new(photo.path).dimensions
  rescue StandardError
    nil
  end

  def slug_base
    name.to_s.parameterize
  end

  def public_path_prefix
    "/catalogue"
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
