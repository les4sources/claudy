# La communication structurée d'une facture de vente (« +++123/4567/89012+++ »),
# telle qu'OkiOki la donne (Michael, 2026-10-30) : le virement du client la
# reprend, c'est l'indice le plus sûr pour rapprocher son paiement.
class AddPaymentReferenceToSalesInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :sales_invoices, :payment_reference, :string
  end
end
