# Les notes de frais et les notes de mission (epic #241, phase 1).
#
# Un seul modèle pour les deux (décision 1) : une note de mission est une note
# de frais dont les lignes sont des kilomètres. `kind` sépare les deux
# formulaires et les deux séquences de pièces, rien d'autre.
#
# `fiscal_year_id` et `sequence_number` ne servent qu'à la référence : la
# séquence est « par exercice et par type », et la tenir dans une colonne rend
# le contrôle de trous (`rake accounting:verify_expense_reports`) exact plutôt
# que dépendant du format du texte de la référence.
class CreateExpenseReports < ActiveRecord::Migration[8.1]
  def change
    create_table :expense_reports do |t|
      t.string :kind, null: false, default: "expenses"
      t.references :human, null: false, foreign_key: true
      t.references :legal_entity, null: false, foreign_key: true
      t.references :fiscal_year, foreign_key: true
      t.string :status, null: false, default: "recorded"
      t.string :reference
      t.integer :sequence_number
      t.date :submitted_on
      t.date :processed_on
      t.date :paid_on
      t.text :rejection_reason
      t.text :notes
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :posted_at
      t.datetime :paid_notified_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :expense_reports, :reference, unique: true
    add_index :expense_reports, %i[fiscal_year_id kind sequence_number],
              unique: true, name: "index_expense_reports_on_sequence"
    add_index :expense_reports, :status
    add_index :expense_reports, :deleted_at

    create_table :expense_lines do |t|
      t.references :expense_report, null: false, foreign_key: true
      t.date :spent_on, null: false
      t.string :label, null: false
      t.string :supplier_name
      t.string :doc_kind
      t.bigint :amount_cents, null: false, default: 0
      t.references :general_account, foreign_key: true
      t.references :team, foreign_key: true
      t.references :analytic_account, foreign_key: true
      t.decimal :distance_km, precision: 8, scale: 1
      t.integer :rate_cents_per_km
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :expense_lines, :deleted_at
  end
end
