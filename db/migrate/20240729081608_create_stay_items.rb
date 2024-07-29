class CreateStayItems < ActiveRecord::Migration[7.0]
  def change
     create_table :stay_items do |t|
      t.references :stay, null: false, foreign_key: true
      t.references :bookable, polymorphic: true, null: false
      t.integer :quantity
      t.decimal :price
      t.timestamps
    end
  end
end
