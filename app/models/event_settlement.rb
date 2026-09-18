# Le règlement d'un événement (epic #245, phase 3) : le partage FIGÉ.
#
# Tant qu'un événement n'est pas réglé, sa part se recalcule à chaque affichage.
# Une fois réglé, les chiffres ne bougent plus — et l'événement se ferme côté
# frais et recettes : une allocation postérieure est refusée, avec un message qui
# renvoie à la contre-passation. Un chiffre qui bouge après le virement, c'est un
# écart qu'on cherche des heures.
class EventSettlement < ApplicationRecord
  STATUSES = %w[issued paid].freeze

  belongs_to :event
  has_many :event_settlement_lines, dependent: :destroy

  has_paper_trail

  monetize :revenue_cents
  monetize :costs_cents
  monetize :base_cents
  monetize :organizers_cents
  monetize :house_cents

  validates :status, inclusion: { in: STATUSES }
  validates :organizer_share_percent, numericality: { only_integer: true, in: 0..100 }
  validate :lines_cover_the_organizer_share

  scope :issued, -> { where(status: "issued") }
  scope :paid, -> { where(status: "paid") }

  def issued? = status == "issued"
  def paid? = status == "paid"
  def posted? = posted_at.present?

  def label = "Règlement — #{event.name}"

  # Réglé quand TOUTES ses lignes le sont. Un règlement dont une seule part reste
  # à virer n'est pas payé : il est partiellement payé, et ça se voit.
  def refresh_status!
    lines = event_settlement_lines.to_a
    settled = lines.any? && lines.all?(&:payable_settled?)
    update!(status: settled ? "paid" : "issued")
  end

  private

  # L'invariant du règlement : la somme des parts vaut EXACTEMENT la part des
  # organisateurs. Sans lui, un centime perdu dans un arrondi devient un écart
  # entre l'écriture et ce qu'on vire.
  def lines_cover_the_organizer_share
    return if event_settlement_lines.empty?

    total = event_settlement_lines.sum { |line| line.amount_cents.to_i }
    return if total == organizers_cents

    errors.add(:base, "La somme des parts (#{total}) ne fait pas la part des organisateurs (#{organizers_cents}).")
  end
end
