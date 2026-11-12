# « Déjà réglée » à l'encodage (Michael, 2026-11-12) : la facture est payée
# avant d'arriver en comptabilité — domiciliation, carte, virement déjà fait,
# billets au marché. On le DÉCLARE, sans cocher « Payée » : le paiement reste un
# rapprochement (décision 4). `settled_via` dit par où l'argent est sorti,
# `settled_on` quand.
class AddSettlementToPurchaseInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_invoices, :settled_via, :string
    add_column :purchase_invoices, :settled_on, :date
  end
end
