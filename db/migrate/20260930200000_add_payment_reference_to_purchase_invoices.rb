# La communication à mettre sur le virement d'une facture d'achat. Souvent une
# communication structurée belge (+++123/4567/89002+++), que le fournisseur
# rapproche automatiquement ; à défaut, le numéro de sa facture reste la
# communication par défaut (`PurchaseInvoice#payable_communication`).
class AddPaymentReferenceToPurchaseInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_invoices, :payment_reference, :string
  end
end
