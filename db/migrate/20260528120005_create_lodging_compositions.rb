class CreateLodgingCompositions < ActiveRecord::Migration[7.0]
  def change
    create_table :lodging_compositions do |t|
      t.bigint :composite_lodging_id, null: false
      t.bigint :component_lodging_id, null: false

      t.timestamps
    end

    add_index :lodging_compositions, :composite_lodging_id
    add_index :lodging_compositions, :component_lodging_id
    add_index :lodging_compositions, [:composite_lodging_id, :component_lodging_id],
              unique: true, name: "index_lodging_compositions_unique_pair"
    add_foreign_key :lodging_compositions, :lodgings, column: :composite_lodging_id
    add_foreign_key :lodging_compositions, :lodgings, column: :component_lodging_id
  end
end
