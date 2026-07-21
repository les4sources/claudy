class CreateCoworkingPacks < ActiveRecord::Migration[7.0]
  def change
    create_table :coworking_packs do |t|
      t.references :customer, null: false, foreign_key: true
      t.integer :days_total, null: false
      t.integer :price_cents, null: false, default: 0
      t.datetime :purchased_at, null: false
      t.datetime :expires_at, null: false
      t.string :payment_method, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :coworking_packs, :deleted_at
    add_index :coworking_packs, :expires_at
  end
end
