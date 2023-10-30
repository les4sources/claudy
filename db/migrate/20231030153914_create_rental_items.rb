class CreateRentalItems < ActiveRecord::Migration[7.0]
  def change
    create_table :rental_items do |t|
      t.string :name
      t.integer :stock
      t.string :photo
      t.text :description
      t.datetime :deleted_at
      t.integer :price_cents

      t.timestamps
    end
  end
end
