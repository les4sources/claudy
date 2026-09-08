# Epic #248, phase 1 — l'artisan qui dépose des produits en dépôt-vente à
# l'épicerie. Les relevés mensuels (`consignment_reports`) arrivent en phase 2.
class CreateConsignors < ActiveRecord::Migration[8.1]
  def change
    create_table :consignors do |t|
      t.string  :name, null: false
      t.string  :email
      t.references :human,       foreign_key: true
      t.references :third_party, foreign_key: true
      t.integer :commission_percent, null: false, default: 20
      t.string  :settlement_mode,    null: false, default: "transfer"
      # Chiffré au repos (Active Record Encryption) : le texte chiffré est plus
      # long que l'IBAN lui-même, d'où le `text`.
      t.text    :iban
      t.date    :starts_on
      t.date    :ends_on
      t.boolean :active, null: false, default: true
      t.text    :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :consignors, :deleted_at
    add_index :consignors, :active
  end
end
