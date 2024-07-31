class CreateNewStayItems < ActiveRecord::Migration[7.0]
  def change
    create_table :stay_items do |t|
      t.references :stay, null: false, foreign_key: true
      t.references :item, polymorphic: true, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :quantity, default: 1
      t.decimal :unit_price, precision: 10, scale: 2
      t.integer :adults_count
      t.integer :children_count
      t.string :duration
      t.timestamps
    end
  end
end
