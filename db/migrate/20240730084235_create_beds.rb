class CreateBeds < ActiveRecord::Migration[7.0]
  def change
    create_table :beds do |t|
      t.string :name
      t.text :description
      t.integer :price_cents
      t.references :room, foreign_key: true, index: true
      t.timestamps
    end
  end
end


