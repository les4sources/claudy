# Les factures d'achat (epic #240, phase 2).
#
# Jusqu'ici, une facture fournisseur vivait dans une boîte mail : rien ne portait
# le PDF, le statut, le compte, le pôle, l'entité — et on découvrait au moment de
# payer que personne n'avait dit oui.
#
# `pdf_sha256` et le couple (tiers, numéro) sont uniques (décision 5) : c'est la
# double couche qui empêche qu'une facture transmise deux fois soit payée deux
# fois.
class CreatePurchaseInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_invoices do |t|
      t.references :legal_entity, null: false, foreign_key: true
      t.references :third_party, null: false, foreign_key: true
      t.string :number
      t.date :issued_on, null: false
      t.date :due_on
      t.integer :total_cents, null: false, default: 0
      t.string :status, null: false, default: "to_process"
      t.boolean :requires_validation, null: false, default: false
      t.references :validation_team, foreign_key: { to_table: :teams }
      t.references :validated_by, foreign_key: { to_table: :users }
      t.datetime :validated_at
      t.text :dispute_reason
      t.datetime :posted_at
      t.date :paid_on
      t.string :pdf_sha256
      t.jsonb :quality_flags, null: false, default: []
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :purchase_invoices, :status
    add_index :purchase_invoices, :deleted_at
    add_index :purchase_invoices, :pdf_sha256, unique: true, where: "deleted_at IS NULL"
    add_index :purchase_invoices, %i[third_party_id number], unique: true,
              where: "deleted_at IS NULL AND number IS NOT NULL",
              name: "index_purchase_invoices_on_third_party_and_number"

    create_table :purchase_invoice_lines do |t|
      t.references :purchase_invoice, null: false, foreign_key: true,
                   index: { name: "index_purchase_lines_on_invoice" }
      t.references :general_account, null: false, foreign_key: true,
                   index: { name: "index_purchase_lines_on_account" }
      t.references :team, foreign_key: true, index: { name: "index_purchase_lines_on_team" }
      t.references :analytic_account, foreign_key: true,
                   index: { name: "index_purchase_lines_on_analytic" }
      t.integer :amount_cents, null: false, default: 0
      t.string :label
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :purchase_invoice_lines, :deleted_at, name: "index_purchase_lines_on_deleted_at"
  end
end
