# Rapprochement assisté (issue #183).
#
# Ce que ces deux tables ne portent PAS est aussi important que ce qu'elles
# portent : il n'existe nulle part de `default_analytic_account_id`. Une règle
# est un objet nommé, ordonné, désactivable, dont chaque proposition laisse une
# trace. Un « compte par défaut » serait la même chose en invisible — et c'est
# exactement le défaut de Winbooks qui a rangé des recettes d'hébergement dans
# le bar sans que personne ne s'en aperçoive.
#
# `allocation_suggestions` est délibérément une table à part, et pas un champ
# sur `cash_allocations` : une suggestion n'est pas une affectation en attente,
# c'est une proposition. La séparation rend impossible qu'une suggestion pèse
# sur un solde par accident.
class CreateAllocationRules < ActiveRecord::Migration[8.1]
  def change
    create_table :allocation_rules do |t|
      t.string :label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      # Critères — tous facultatifs, tous cumulatifs. Une règle sans aucun
      # critère est refusée par le modèle : elle matcherait tout.
      t.string :counterparty_iban
      t.string :counterparty_name_contains
      t.string :communication_contains
      t.string :transaction_code
      t.string :direction # incoming / outgoing / nil = les deux
      t.bigint :min_amount_cents
      t.bigint :max_amount_cents

      # Cible proposée
      t.references :general_account, null: false, foreign_key: true
      t.references :analytic_account, foreign_key: true
      t.references :team, foreign_key: true
      t.references :legal_entity, null: false, foreign_key: true

      t.integer :confidence, null: false, default: 80
      t.integer :accepted_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :allocation_rules, :position
    add_index :allocation_rules, :deleted_at

    create_table :allocation_suggestions do |t|
      t.references :cash_entry, null: false, foreign_key: true
      t.references :allocation_rule, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.references :analytic_account, foreign_key: true
      t.references :team, foreign_key: true
      t.references :legal_entity, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.integer :confidence, null: false, default: 50
      t.string :source, null: false, default: "rule" # rule / iban_history
      t.text :rationale, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :decided_at
      t.string :decided_by
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :allocation_suggestions, [:cash_entry_id, :status]
    add_index :allocation_suggestions, :deleted_at
  end
end
