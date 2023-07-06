class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :name
      t.integer :stock
      t.string :photo
      t.text :description
      t.timestamp :deleted_at

      t.timestamps
    end

    add_monetize :products, :price, amount: { null: true, default: nil }, currency: { present: false }
  end
end
