class CreateKitchenProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchen_products do |t|
      t.string  :name, null: false
      t.string  :unit, null: false
      t.decimal :quantity_per_person, precision: 8, scale: 2, null: false
      # Types de prestation concernés (buffet_vege, buffet_viande, apero) — un
      # produit sans type ne sort jamais dans une liste de courses.
      t.jsonb   :kinds, null: false, default: []
      t.string  :note
      t.integer :position
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :kitchen_products, :kinds, using: :gin
  end
end
