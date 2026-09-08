# Epic #243, phase 1 — les motifs de caisse. Décision 2 : le motif EST
# l'affectation. Il porte le compte général, le pôle, l'entité et le sens ;
# saisir une ligne de caisse revient alors à choisir un motif et un montant.
class CreateCashMotifs < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_motifs do |t|
      t.string  :label, null: false
      t.string  :direction, null: false, default: "both"
      t.references :general_account, null: false, foreign_key: true
      t.references :team,            foreign_key: true
      t.references :legal_entity,    null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.boolean :active,   null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cash_motifs, :deleted_at
    add_index :cash_motifs, %i[position id]
  end
end
