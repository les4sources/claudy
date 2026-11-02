# Les notes de crédit fournisseurs (Michael, 2026-11-01) : une pièce d'achat
# est une facture ou une note de crédit, qui peut pointer la facture qu'elle
# corrige. Montants toujours positifs : c'est le type qui inverse l'écriture.
class AddCreditNotesToPurchaseInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_invoices, :kind, :string, null: false, default: "invoice"
    add_reference :purchase_invoices, :credited_invoice, foreign_key: { to_table: :purchase_invoices }, index: true

    # Un fournisseur peut numéroter ses notes de crédit à part : la note 26030
    # et la facture 26030 ne sont pas la même pièce.
    remove_index :purchase_invoices, name: "index_purchase_invoices_on_third_party_and_number",
                                     column: %i[third_party_id number], unique: true,
                                     where: "deleted_at IS NULL AND number IS NOT NULL"
    add_index :purchase_invoices, %i[third_party_id kind number], unique: true,
                                  where: "deleted_at IS NULL AND number IS NOT NULL",
                                  name: "index_purchase_invoices_on_third_party_and_number"
  end
end
