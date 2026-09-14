# Une ligne du relevé de dépôt-vente : un article, une quantité, un prix unitaire
# (epic #248, phase 2).
#
# Le montant est CALCULÉ et stocké : l'artisan ne le tape pas, et il reste lisible
# tel quel dans dix-huit mois même si on change la façon de le calculer.
class ConsignmentReportLine < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :consignment_report

  before_validation :compute_amount

  validates :label, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }

  private

  def compute_amount
    self.quantity = 1 if quantity.blank?
    self.unit_price_cents = 0 if unit_price_cents.blank?
    self.amount_cents = quantity.to_i * unit_price_cents.to_i
  end
end
