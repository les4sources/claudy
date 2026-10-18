# Le budget détaillé (étape 4 du redressement, Michael, 2026-10-18) : un
# montant annuel par entité, pôle et compte de charges ou de produits. Le pôle
# est facultatif : ce qui n'appartient à aucun pôle se budgète aussi, sinon le
# total de l'entité serait faux.
class CreateBudgetLines < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_lines do |t|
      t.integer :year, null: false
      t.references :legal_entity, null: false, foreign_key: true
      t.references :team, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.bigint :amount_cents, null: false, default: 0
      t.timestamps
    end
    # Une ligne « sans pôle » est unique elle aussi : COALESCE plutôt qu'un
    # index qui laisserait passer deux NULL.
    add_index :budget_lines, "year, legal_entity_id, COALESCE(team_id, 0), general_account_id",
              unique: true, name: "index_budget_lines_unique_cell"
  end
end
