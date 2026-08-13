# Décomptes mensuels (issue #160).
#
# Un décompte n'est pas un affichage, c'est un DOCUMENT FIGÉ : il gèle quatre
# montants et verrouille les écritures qu'il couvre. Sans ce gel, un décompte
# envoyé par mail se met à mentir dès que quelqu'un corrige une ligne du mois
# passé, et plus personne ne fait confiance au chiffre.
#
# L'index unique (compte, mois) n'est pas décoratif : c'est lui qui garantit
# qu'une double émission concurrente produit UN seul décompte, là où le verrou
# pessimiste seul laisserait passer deux processus arrivés en même temps.
class CreateAccountStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :account_statements do |t|
      t.references :member_account, null: false, foreign_key: true
      t.date :period_month, null: false
      t.string :status, null: false, default: "draft"
      t.bigint :opening_balance_cents, null: false, default: 0
      t.bigint :debits_cents, null: false, default: 0
      t.bigint :credits_cents, null: false, default: 0
      t.bigint :closing_balance_cents, null: false, default: 0
      t.string :token, null: false
      t.datetime :issued_at
      t.datetime :sent_at
      t.integer :reminders_count, null: false, default: 0
      t.datetime :last_reminder_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :account_statements, [:member_account_id, :period_month], unique: true
    add_index :account_statements, :token, unique: true
    add_index :account_statements, :deleted_at

    add_foreign_key :account_entries, :account_statements
  end
end
