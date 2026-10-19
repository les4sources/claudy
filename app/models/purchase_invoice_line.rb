# Une ligne de ventilation d'une facture d'achat (epic #240, phase 2).
#
# C'est elle qui porte le compte de charge, le pôle et l'analytique : une facture
# de bricolage peut se répartir entre le pôle Technique et le pôle Accueil, et
# c'est la seule façon de savoir plus tard ce que chaque pôle a vraiment dépensé.
#
# Le montant se tape HTVA avec son taux, comme sur la pièce ; `amount_cents`
# garde ce que la ligne coûte TVA comprise (c'est lui qui couvre le total) et
# `vat_cents` sa part de TVA. La TVA se calcule à l'échelle de la facture, taux
# par taux (`PurchaseInvoice#compute_vat`), comme le fournisseur l'a calculée.
class PurchaseInvoiceLine < ApplicationRecord
  # Les taux belges. 0 : une ligne déjà TVAC, ou un fournisseur sans TVA.
  VAT_RATES = [21, 12, 6, 0].freeze
  DEFAULT_VAT_RATE = 21
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :purchase_invoice
  belongs_to :general_account
  belongs_to :team, optional: true
  belongs_to :analytic_account, optional: true

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :vat_rate, inclusion: { in: VAT_RATES }

  # Le HTVA tapé dans le formulaire. Posé, il fait recalculer la TVA et le
  # montant TVAC par la facture ; absent (outil MCP, pièce lue d'un mail), la
  # ligne garde le montant qu'on lui a donné.
  attr_reader :net_cents

  def net_cents=(value)
    @net_cents = value.nil? ? nil : value.to_i
  end

  def net_amount_cents = amount_cents.to_i - vat_cents.to_i

  scope :ordered, -> { order(:position, :id) }

  def display_label = label.presence || general_account&.to_s
end
