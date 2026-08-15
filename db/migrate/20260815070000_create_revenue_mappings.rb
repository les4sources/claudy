# Correspondance catégorie de devis → compte de recette (issue #185).
#
# Le compte général est mécanique : une nuitée est un produit d'hébergement, un
# repas est un produit de repas. Le PÔLE, lui, ne l'est pas — savoir quel pôle
# porte l'hébergement est une décision de gouvernance du collectif. La colonne
# existe donc, et reste vide jusqu'à ce que Michael la remplisse.
#
# `customer_bank_accounts` : l'IBAN d'un client, mémorisé à chaque rapprochement
# validé par un humain. C'est ce qui fait qu'au deuxième séjour d'un client
# récurrent, le virement se rattache tout seul.
class CreateRevenueMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :revenue_mappings do |t|
      t.string :category, null: false
      t.references :general_account, null: false, foreign_key: true
      t.references :team, foreign_key: true
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :revenue_mappings, :category, unique: true
    add_index :revenue_mappings, :deleted_at

    create_table :customer_bank_accounts do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :iban, null: false
      t.string :holder_name
      t.integer :matches_count, null: false, default: 0
      t.datetime :last_matched_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :customer_bank_accounts, [:iban, :customer_id], unique: true
    add_index :customer_bank_accounts, :deleted_at
  end
end
