# Une ligne de ventilation d'une facture d'achat (epic #240, phase 2).
#
# C'est elle qui porte le compte de charge, le pôle et l'analytique : une facture
# de bricolage peut se répartir entre le pôle Technique et le pôle Accueil, et
# c'est la seule façon de savoir plus tard ce que chaque pôle a vraiment dépensé.
class PurchaseInvoiceLine < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :purchase_invoice
  belongs_to :general_account
  belongs_to :team, optional: true
  belongs_to :analytic_account, optional: true

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }

  scope :ordered, -> { order(:position, :id) }

  def display_label = label.presence || general_account&.to_s
end
