# Un exercice comptable — la borne temporelle qui rend une écriture définitive.
#
# Sans exercice clôturable, « verrouillé » n'est qu'une politesse : il resterait
# toujours un chemin pour retoucher le passé. La clôture est ce qui transforme
# la promesse en interdit.
# == Schema Information
#
# Table name: fiscal_years
#
#  id              :bigint           not null, primary key
#  closed_at       :datetime
#  deleted_at      :datetime
#  ends_on         :date             not null
#  starts_on       :date             not null
#  status          :string           default("open"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  legal_entity_id :bigint           not null
#
# Indexes
#
#  index_fiscal_years_on_deleted_at                     (deleted_at)
#  index_fiscal_years_on_legal_entity_id                (legal_entity_id)
#  index_fiscal_years_on_legal_entity_id_and_starts_on  (legal_entity_id,starts_on) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#
class FiscalYear < ApplicationRecord
  STATUSES = %w[open closed].freeze
  STATUS_LABELS = { "open" => "Ouvert", "closed" => "Clôturé" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  has_many :journal_entries, dependent: :restrict_with_error

  validates :starts_on, :ends_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :ends_after_start
  validate :no_overlap
  validate :dates_frozen_once_closed, on: :update

  before_destroy :refuse_destruction_when_closed

  scope :ordered, -> { order(starts_on: :desc) }
  scope :opened, -> { where(status: "open") }

  def status_label = STATUS_LABELS.fetch(status, status)
  def covers?(date) = date.present? && starts_on <= date && date <= ends_on
  def closed? = status == "closed"
  def label = "#{starts_on.year}"

  def close!
    update!(status: "closed", closed_at: Time.current)
  end

  private

  # Redater un exercice clôturé ferait basculer des écritures définitives d'un
  # exercice à l'autre. Rouvrir reste possible — c'est un acte délibéré, tracé
  # par PaperTrail — mais bouger ses bornes, non.
  def dates_frozen_once_closed
    return unless status_was == "closed"
    return if (changed & %w[starts_on ends_on legal_entity_id]).empty?

    errors.add(:base, "Un exercice clôturé ne se redate pas — rouvre-le d'abord si c'est vraiment ce que tu veux")
  end

  def refuse_destruction_when_closed
    return unless closed?

    errors.add(:base, "Un exercice clôturé ne se supprime pas")
    throw :abort
  end

  def ends_after_start
    return if starts_on.blank? || ends_on.blank? || ends_on > starts_on

    errors.add(:ends_on, "doit suivre la date de début")
  end

  # Deux exercices qui se chevauchent, c'est une écriture qui peut tomber dans
  # deux exercices à la fois — et donc une balance qui dépend de l'ordre de
  # lecture.
  def no_overlap
    return if legal_entity_id.blank? || starts_on.blank? || ends_on.blank?

    conflicting = FiscalYear.where(legal_entity_id: legal_entity_id)
                            .where.not(id: id)
                            .where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on)
    return unless conflicting.exists?

    errors.add(:base, "Cet exercice en chevauche un autre pour la même entité")
  end
end
