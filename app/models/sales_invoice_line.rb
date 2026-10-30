# Une ligne d'une facture de vente : le compte de produit (classe 7), le
# libellé, le montant, la TVA, le pôle et l'analytique. Le pendant de
# `PurchaseInvoiceLine` (Michael, 2026-10-30).
#
# Le montant se tape HTVA avec son taux, comme sur la facture OkiOki ;
# `amount_cents` garde ce que la ligne vaut TVA comprise (c'est lui qui couvre
# le total) et `vat_cents` sa part de TVA. La TVA se calcule à l'échelle de la
# facture, taux par taux (`SalesInvoice#compute_vat`), sauf quand on la donne
# telle que la facture l'affiche (import, outil MCP).
# == Schema Information
#
# Table name: sales_invoice_lines
#
#  id                  :bigint           not null, primary key
#  amount_cents        :integer          default(0), not null
#  deleted_at          :datetime
#  label               :string
#  position            :integer          default(0), not null
#  vat_cents           :integer          default(0), not null
#  vat_rate            :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  analytic_account_id :bigint
#  general_account_id  :bigint           not null
#  sales_invoice_id    :bigint           not null
#  team_id             :bigint
#
# Indexes
#
#  index_sales_invoice_lines_on_analytic_account_id  (analytic_account_id)
#  index_sales_invoice_lines_on_deleted_at           (deleted_at)
#  index_sales_invoice_lines_on_general_account_id   (general_account_id)
#  index_sales_invoice_lines_on_sales_invoice_id     (sales_invoice_id)
#  index_sales_invoice_lines_on_team_id              (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (sales_invoice_id => sales_invoices.id)
#  fk_rails_...  (team_id => teams.id)
#
class SalesInvoiceLine < ApplicationRecord
  VAT_RATES = PurchaseInvoiceLine::VAT_RATES

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :sales_invoice, inverse_of: :sales_invoice_lines
  belongs_to :general_account
  belongs_to :team, optional: true
  belongs_to :analytic_account, optional: true

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :vat_rate, inclusion: { in: VAT_RATES }
  validate :revenue_account

  # Le HTVA tapé. Posé, il fait recalculer la TVA et le TVAC par la facture ;
  # absent, la ligne garde les montants qu'on lui a donnés.
  attr_reader :net_cents

  def net_cents=(value)
    @net_cents = value.nil? ? nil : value.to_i
  end

  # La TVA telle que la facture l'affiche. Donnée avec le HTVA, elle remplace
  # le calcul : c'est OkiOki qui fait foi, pas l'arrondi de Claudy.
  attr_reader :typed_vat_cents

  def typed_vat_cents=(value)
    @typed_vat_cents = value.nil? ? nil : value.to_i
  end

  def net_amount_cents = amount_cents.to_i - vat_cents.to_i

  def display_label = label.presence || general_account&.to_s

  private

  def revenue_account
    return if general_account.blank? || general_account.klass == 7

    errors.add(:general_account, "doit être un compte de produit (classe 7)")
  end
end
