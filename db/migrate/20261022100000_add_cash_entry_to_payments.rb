# Un paiement de séjour peut venir de la BANQUE (Michael, 2026-10-22) : quand
# une ligne de trésorerie est ventilée sur un séjour, le séjour reçoit son
# paiement, relié à la ligne. `created_from_cash_entry` distingue le paiement
# créé par l'affectation (qui disparaît avec elle) de celui que l'Accueil avait
# déjà encodé et qu'on n'a fait que relier (qui reste, simplement détaché).
class AddCashEntryToPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :payments, :cash_entry, type: :bigint, foreign_key: { on_delete: :nullify }, index: true
    add_column :payments, :created_from_cash_entry, :boolean, default: false, null: false
  end
end
