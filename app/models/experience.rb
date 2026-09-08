# == Schema Information
#
# Table name: experiences
#
#  id                        :bigint           not null, primary key
#  carrier_hourly_rate_cents :integer
#  color                     :string
#  deleted_at                :datetime
#  description               :text
#  duration                  :string
#  duration_hours            :decimal(4, 2)
#  fixed_price_cents         :integer          default(0)
#  max_participants          :integer
#  min_participants          :integer
#  name                      :string
#  photo                     :string
#  price_cents               :integer
#  published_at              :datetime
#  slug                      :string
#  summary                   :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  human_id                  :bigint
#  team_id                   :bigint
#
# Indexes
#
#  index_experiences_on_human_id  (human_id)
#  index_experiences_on_slug      (slug) UNIQUE
#  index_experiences_on_team_id   (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (team_id => teams.id)
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
  # Le pôle qui porte la charge de la rémunération (epic #244, décision 6).
  belongs_to :team, optional: true

  has_many :experience_availabilities, dependent: :destroy
  has_many :experience_bookings, through: :experience_availabilities

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  monetize :price_cents, allow_nil: true
  monetize :fixed_price_cents, allow_nil: true

  mount_uploader :photo, PhotoUploader

  validates :carrier_hourly_rate_cents,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

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

  # --- Rémunération du porteur (epic #244, phase 1) ---
  #
  # Le tarif horaire effectif : celui de l'activité s'il est posé, sinon le
  # tarif général `activity.carrier_hourly`. Avec `on:`, on lit le tarif EN
  # VIGUEUR à cette date — c'est ce qui permet de figer une prestation au tarif
  # du jour de son créneau plutôt qu'au tarif d'aujourd'hui.
  def effective_carrier_hourly_cents(on: nil)
    return carrier_hourly_rate_cents if carrier_hourly_rate_cents.present?

    Pricing::Catalog.activity_carrier_hourly_cents(on: on)
  end

  # true quand le tarif vient de l'activité et non du barème général.
  def carrier_rate_overridden? = carrier_hourly_rate_cents.present?

  # Le formulaire saisit des EUROS ; la base tient des cents. La virgule
  # décimale est acceptée — c'est celle qu'on tape en français.
  def carrier_hourly_rate
    carrier_hourly_rate_cents.present? ? carrier_hourly_rate_cents / 100.0 : nil
  end

  def carrier_hourly_rate=(value)
    raw = value.to_s.strip.tr(",", ".")
    self.carrier_hourly_rate_cents = raw.blank? ? nil : (raw.to_f * 100).round
  end

  # Rémunération d'UNE prestation — par prestation, jamais par participant
  # (décision 1). nil quand la durée manque : sans durée, pas de montant, et
  # l'écran doit le dire plutôt que d'inventer un zéro.
  def carrier_fee_cents_on(date = nil)
    return nil if duration_hours.blank? || duration_hours.to_d <= 0

    (duration_hours.to_d * effective_carrier_hourly_cents(on: date)).round
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
