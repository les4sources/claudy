class CreateLinenOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :linen_orders do |t|
      t.references :stay, null: false, foreign_key: true
      t.string  :kind, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents
      t.integer :price_cents
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :linen_orders, :deleted_at
    add_index :linen_orders, %i[stay_id kind], unique: true, where: "deleted_at IS NULL",
              name: "index_linen_orders_on_stay_and_kind_unique_live"
  end
end
