# == Schema Information
#
# Table name: rate_versions
#
#  id           :bigint           not null, primary key
#  active_from  :date             not null
#  active_until :date
#  amount_cents :integer          not null
#  note         :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  rate_id      :bigint           not null
#
# Indexes
#
#  index_rate_versions_on_rate_id                  (rate_id)
#  index_rate_versions_on_rate_id_and_active_from  (rate_id,active_from) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (rate_id => rates.id)
#

# Une valeur datée d'une clé du barème (issue #156).
#
# La période est fermée à gauche, ouverte ou fermée à droite :
# `[active_from, active_until]` inclusive des deux bornes, `active_until = nil`
# signifiant « jusqu'à nouvel ordre ». Deux versions d'une même clé ne peuvent
# pas se chevaucher — sinon `cents(key, on:)` n'aurait plus de réponse unique.
class RateVersion < ApplicationRecord
  # Origine conventionnelle des barèmes repris : la reprise d'historique du lot A
  # remonte à 2023, aucune lecture datée ne demande plus ancien.
  ORIGIN = Date.new(2023, 1, 1).freeze

  belongs_to :rate, inverse_of: :rate_versions

  validates :amount_cents,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :active_from, presence: true
  validate :active_until_after_active_from
  validate :no_overlap_with_siblings

  scope :chronological, -> { order(active_from: :asc) }
  scope :most_recent_first, -> { order(active_from: :desc) }

  # Les versions dont la période couvre `date`.
  scope :covering, lambda { |date|
    where(active_from: ..date)
      .where("rate_versions.active_until IS NULL OR rate_versions.active_until >= ?", date)
  }

  def covers?(date)
    return false if active_from.nil? || date.nil?

    active_from <= date && (active_until.nil? || active_until >= date)
  end

  def current? = covers?(Date.current)

  def open_ended? = active_until.nil?

  private

  def active_until_after_active_from
    return if active_until.blank? || active_from.blank?
    return if active_until >= active_from

    errors.add(:active_until, "doit être postérieure ou égale à la date de début")
  end

  # Deux périodes se chevauchent dans exactement deux configurations : soit la
  # voisine commence avant (ou le même jour) et couvre alors notre date de
  # début, soit elle commence après et tombe dans notre propre période.
  def no_overlap_with_siblings
    return if rate_id.blank? || active_from.blank?

    if siblings.covering(active_from).exists?
      return errors.add(:active_from, "chevauche une version existante de ce tarif")
    end

    later = active_until.blank? ? siblings.where(active_from: active_from..)
                                : siblings.where(active_from: active_from..active_until)
    return unless later.exists?

    errors.add(:active_until, "chevauche une version existante de ce tarif")
  end

  def siblings
    scope = RateVersion.where(rate_id: rate_id)
    persisted? ? scope.where.not(id: id) : scope
  end
end
