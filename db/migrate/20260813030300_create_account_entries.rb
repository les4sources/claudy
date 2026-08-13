# Grand livre (issue #155).
#
# Le montant est SIGNÉ : positif = dû par le compte, négatif = en sa faveur
# (règlement, avoir). C'est ce choix qui permettra d'ajouter le côté créditeur
# — rémunérations, dépôt-vente — sans migration structurante : ce ne sera qu'un
# nouveau `kind` au montant négatif. Une écriture à zéro n'existe pas, et c'est
# la base qui le refuse.
#
# `account_statement_id` arrive DÉLIBÉRÉMENT sans clé étrangère : la table
# `account_statements` est créée en phase 6. La colonne est là dès maintenant
# parce que c'est elle qui verrouille une écriture rattachée à un décompte émis.
class CreateAccountEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :account_entries do |t|
      t.references :member_account, null: false, foreign_key: true, index: false
      t.date :entry_date, null: false
      t.datetime :posted_at
      t.bigint :amount_cents, null: false
      t.string :flow
      t.string :kind
      t.string :label
      t.decimal :quantity, precision: 12, scale: 3
      t.integer :unit_price_cents
      t.string :price_basis
      t.string :source
      t.string :idempotency_key
      t.string :client_uuid
      t.bigint :account_statement_id
      t.datetime :locked_at
      t.bigint :reversal_of_id
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :account_entries, [:member_account_id, :entry_date]
    add_index :account_entries, :idempotency_key, unique: true
    add_index :account_entries, :client_uuid, unique: true
    add_index :account_entries, :account_statement_id
    add_index :account_entries, :reversal_of_id
    add_index :account_entries, :deleted_at

    add_foreign_key :account_entries, :account_entries, column: :reversal_of_id

    add_check_constraint :account_entries, "amount_cents <> 0",
                         name: "account_entries_amount_not_zero_check"
  end
end
