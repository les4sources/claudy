# Le registre des factures de vente (epic #240, phase 6).
#
# Les factures de vente sont émises dans OkiOki, qui n'a pas d'API : Claudy ne
# les ÉMET pas, il les ENREGISTRE — numéro, date, montant, PDF — et les relie à
# ce qu'elles facturent. C'est ce lien qui garantit qu'un séjour ne part pas
# deux fois en facture.
#
# Aucune écriture comptable n'est générée ici (décision 8) : la recette est
# déjà comptabilisée par la ventilation de la ligne bancaire.
class CreateSalesInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_invoices do |t|
      t.references :legal_entity, null: false, foreign_key: true
      # Facultatif : une facture historique peut ne pas avoir de client en base.
      t.references :customer, foreign_key: true
      t.string :number, null: false
      t.date :issued_on, null: false
      t.bigint :total_cents, null: false, default: 0
      t.string :status, null: false, default: "issued"
      t.date :paid_on
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    # Le numéro OkiOki est unique PAR ENTITÉ : la fondation et la SRL ont chacune
    # leur séquence, et deux « 2026-001 » coexistent légitimement.
    add_index :sales_invoices, [:legal_entity_id, :number], unique: true
    add_index :sales_invoices, :deleted_at
    add_index :sales_invoices, :status

    create_table :sales_invoice_sources do |t|
      t.references :sales_invoice, null: false, foreign_key: true
      t.references :source, polymorphic: true, null: false

      t.timestamps
    end

    # C'EST L'INVARIANT DE LA PHASE : une source ne peut être facturée qu'une
    # fois. Tenu en base, pas seulement par une validation — deux clics
    # simultanés passent à travers une validation, pas à travers un index.
    add_index :sales_invoice_sources, [:source_type, :source_id], unique: true,
              name: "index_sales_invoice_sources_on_source_uniqueness"
  end
end
