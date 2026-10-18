# Le budget annuel d'un pôle (Michael, 2026-10-18) : ce qu'il compte produire
# et ce qu'il compte dépenser sur l'année, toutes entités confondues. Deux
# montants, pas un budget par compte : c'est ce qu'il faut à la page du pôle
# pour dire « où en est-on ». L'outil de budget détaillé (entité × pôle ×
# compte, étape 4 du redressement) pourra un jour le remplir.
class CreateTeamBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :team_budgets do |t|
      t.references :team, null: false, foreign_key: true
      t.integer :year, null: false
      t.bigint :revenue_cents, null: false, default: 0
      t.bigint :expense_cents, null: false, default: 0
      t.text :notes
      t.timestamps
    end
    add_index :team_budgets, %i[team_id year], unique: true
    add_check_constraint :team_budgets, "revenue_cents >= 0 AND expense_cents >= 0",
                         name: "team_budgets_amounts_positive"
  end
end
