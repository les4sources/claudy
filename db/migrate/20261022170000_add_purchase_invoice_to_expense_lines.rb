# Une facture d'achat payée en magasin par un membre (Michael, 2026-10-22) :
# la dépense se rembourse par sa note de frais, et c'est la ligne de la note
# qui porte la charge. Le lien dit quelle facture cette ligne règle, pour que
# la facture ne se comptabilise pas une seconde fois.
class AddPurchaseInvoiceToExpenseLines < ActiveRecord::Migration[8.1]
  def change
    add_reference :expense_lines, :purchase_invoice, foreign_key: true, index: true
  end
end
