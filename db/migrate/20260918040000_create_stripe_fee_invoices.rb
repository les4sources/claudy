# Le justificatif mensuel des frais Stripe (epic #240, phase 5).
#
# Les frais sont DÉJÀ comptabilisés par la ventilation des versements : ce
# document ne crée aucune écriture, il archive la pièce que réclame un contrôle
# et donne l'écart avec ce que Claudy a compté. Un par compte Stripe et par mois.
class CreateStripeFeeInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_fee_invoices do |t|
      t.string  :account_key, null: false
      t.date    :period_month, null: false
      t.integer :declared_fee_cents
      t.string  :reference
      t.text    :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stripe_fee_invoices, :deleted_at
    add_index :stripe_fee_invoices, %i[account_key period_month], unique: true,
              where: "deleted_at IS NULL",
              name: "index_stripe_fee_invoices_on_account_and_month_live"
  end
end
