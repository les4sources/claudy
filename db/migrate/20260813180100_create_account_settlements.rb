# Règlements reçus (issue #160).
#
# `received_channel` est DISTINCT du compte réglé, et c'est tout l'intérêt :
# « 20 € glissés dans la caisse de l'épicerie pour régler le bar » se saisit
# enfin tel quel, alors qu'aujourd'hui c'est invérifiable faute d'endroit où
# l'écrire.
#
# `reference` garde la communication BRUTE, même fausse — c'est elle qui permet
# de retrouver ce qu'a vraiment tapé le payeur. `bank_reference` reste vide pour
# l'instant : elle accueillera l'import CODA du lot B sans nouvelle migration.
class CreateAccountSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :account_settlements do |t|
      t.references :member_account, null: false, foreign_key: true
      t.references :account_entry, foreign_key: true
      t.bigint :amount_cents, null: false
      t.date :received_on, null: false
      t.string :method, null: false, default: "bank_transfer"
      t.string :received_channel, null: false, default: "bank"
      t.string :reference
      t.string :bank_reference
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :account_settlements, :received_on
    add_index :account_settlements, :deleted_at
  end
end
