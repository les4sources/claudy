# Fiches papier du bar et de l'épicerie (issue #158).
#
# La fiche reste la pièce justificative : elle est photographiée et attachée,
# ce qui permet de retrouver l'origine d'une ligne contestée. Les écritures
# encodées depuis une fiche portent son `paper_sheet_id` — c'est ce lien qui
# rend l'encodage rejouable et vérifiable, colonne par colonne.
class CreatePaperSheets < ActiveRecord::Migration[8.1]
  def change
    create_table :paper_sheets do |t|
      t.date :period_month, null: false
      t.string :channel, null: false
      t.string :status, null: false, default: "open"
      t.references :member_account, foreign_key: true
      t.string :entry_mode, null: false, default: "quantity"
      t.text :notes
      t.datetime :encoded_at
      t.references :encoded_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :paper_sheets, [:period_month, :channel]
    add_index :paper_sheets, :deleted_at

    add_reference :account_entries, :paper_sheet, foreign_key: true
  end
end
