class CreateRates < ActiveRecord::Migration[7.0]
  def change
    create_table :rates do |t|
      t.string :key, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string :label
      t.string :unit, null: false, default: "cents"

      t.timestamps
    end

    add_index :rates, :key, unique: true
  end
end
