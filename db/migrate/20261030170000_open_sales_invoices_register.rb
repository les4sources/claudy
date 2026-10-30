# Toute facture de vente a sa place au registre, pas seulement celles d'une
# réservation (Michael, 2026-10-30).
#
# - `third_party_id` : le tiers client, le même référentiel que le 400000 ;
#   obligatoire quand rien n'est facturé depuis la file (contrôlé par le modèle).
# - `kind` : facture ou note de crédit, et `credited_invoice_id` pour la facture
#   qu'une note de crédit corrige.
# - `posting_mode` : `on_issue`, l'écriture de vente se passe à l'enregistrement ;
#   `on_payment`, la recette vient de la ventilation du séjour à l'encaissement
#   (le circuit d'avant). Les factures déjà au registre facturent toutes une
#   réservation : elles restent `on_payment`.
# - `journal_entry_id` : l'écriture de vente de la facture (la sienne, ou une
#   écriture reprise à laquelle on la rattache).
class OpenSalesInvoicesRegister < ActiveRecord::Migration[8.1]
  def change
    change_table :sales_invoices, bulk: true do |t|
      t.references :third_party, foreign_key: true, index: true
      t.string :kind, null: false, default: "invoice"
      t.references :credited_invoice, foreign_key: { to_table: :sales_invoices }, index: true
      t.string :posting_mode, null: false, default: "on_payment"
      t.references :journal_entry, foreign_key: true, index: true
      t.datetime :posted_at
    end

    create_table :sales_invoice_lines do |t|
      t.references :sales_invoice, null: false, foreign_key: true, index: true
      t.references :general_account, null: false, foreign_key: true, index: true
      t.references :team, foreign_key: true, index: true
      t.references :analytic_account, foreign_key: true, index: true
      t.string :label
      # TVA comprise : c'est lui qui couvre le total de la facture. Le HTVA est
      # `amount_cents - vat_cents`, comme pour les lignes d'achat.
      t.integer :amount_cents, null: false, default: 0
      t.integer :vat_rate, null: false, default: 0
      t.integer :vat_cents, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at, index: true
      t.timestamps
    end
  end
end
