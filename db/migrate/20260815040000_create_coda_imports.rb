# Import CODA (issue #181).
#
# Deux tables parce qu'il y a deux niveaux d'idempotence à tenir. Le FICHIER
# porte son sha256 : redéposer exactement le même fichier ne doit rien créer. Le
# RELEVÉ porte son couple (compte, année, numéro) : un relevé déjà importé ne
# rentre pas une seconde fois, même s'il arrive dans un autre fichier — et c'est
# le cas courant, les banques renvoient volontiers des fichiers qui se
# chevauchent.
#
# `coda_statements` sert aussi de mémoire du chaînage : c'est en comparant
# l'ancien solde d'un relevé au dernier nouveau solde importé qu'on détecte le
# relevé manquant, celui que l'export bancaire a sauté sans le dire.
class CreateCodaImports < ActiveRecord::Migration[8.1]
  def change
    create_table :coda_imports do |t|
      t.string :filename, null: false
      t.string :sha256, null: false
      t.text :content, null: false
      t.date :creation_date
      t.string :file_reference
      t.string :status, null: false, default: "pending"
      t.integer :statements_count, null: false, default: 0
      t.integer :entries_count, null: false, default: 0
      t.text :report
      t.string :whodunnit
      t.datetime :imported_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :coda_imports, :sha256, unique: true
    add_index :coda_imports, :deleted_at

    create_table :coda_statements do |t|
      t.references :coda_import, null: false, foreign_key: true
      t.references :cash_account, null: false, foreign_key: true
      t.string :sequence_number, null: false
      t.integer :period_year, null: false
      t.bigint :old_balance_cents, null: false
      t.bigint :new_balance_cents, null: false
      t.date :old_balance_date
      t.date :new_balance_date
      t.integer :entries_count, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :coda_statements, [:cash_account_id, :period_year, :sequence_number],
              unique: true, name: "index_coda_statements_on_account_and_sequence"
    add_index :coda_statements, :deleted_at
  end
end
