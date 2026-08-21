class CreateLedgerDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_documents do |t|
      t.string :source_system, null: false
      t.string :external_ref, null: false
      t.date :document_date, null: false
      t.string :label, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :ledger_documents, %i[source_system external_ref], unique: true
    add_index :ledger_documents, :deleted_at

    add_reference :cash_allocations, :third_party, foreign_key: true, index: true
  end
end
