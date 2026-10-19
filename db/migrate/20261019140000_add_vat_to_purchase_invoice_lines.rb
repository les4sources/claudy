# Une facture fournisseur se lit HTVA ligne par ligne, puis TVA, puis TVAC.
# Sans taux sur la ligne, on tapait le HTVA lu sur la pièce et l'écran disait
# qu'il restait la TVA à ventiler (Michael, 2026-10-19, facture 2026-014 du
# Domaine d'Ahinvaux). `amount_cents` reste ce que coûte la ligne, TVA
# comprise : c'est lui qui couvre le total, et tous les lecteurs existants
# continuent de le lire tel quel. `vat_cents` en est la part de TVA.
class AddVatToPurchaseInvoiceLines < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_invoice_lines, :vat_rate, :integer, null: false, default: 0
    add_column :purchase_invoice_lines, :vat_cents, :integer, null: false, default: 0
  end
end
