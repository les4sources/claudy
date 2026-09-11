# Le comptage de la caisse (epic #243, phase 3).
#
# `expected_cents` et `difference_cents` sont FIGÉS à la validation (décision 3)
# et jamais recalculés : un écart qu'on recalcule à l'affichage se dissout au
# premier mouvement saisi après coup, et c'est exactement ce qu'on essaie
# d'arrêter — les −628 € de la caisse venaient de là.
class CreateCashCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_counts do |t|
      t.references :cash_account, null: false, foreign_key: true
      t.date :counted_on, null: false
      # { "50.0" => 2, "0.5" => 7 } — la grille telle qu'elle a été tapée. On la
      # garde pour pouvoir refaire le calcul à la main, un mois plus tard.
      t.jsonb :denominations, null: false, default: {}
      t.integer :counted_cents, null: false, default: 0
      t.integer :expected_cents, null: false, default: 0
      t.integer :difference_cents, null: false, default: 0
      t.text :comment
      t.string :status, null: false, default: "draft"
      t.string :resolution
      t.datetime :validated_at
      t.references :adjustment_cash_entry, foreign_key: { to_table: :cash_entries }
      t.references :counted_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cash_counts, :deleted_at
    add_index :cash_counts, [:cash_account_id, :counted_on]
  end
end
