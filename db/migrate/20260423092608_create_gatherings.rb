class CreateGatherings < ActiveRecord::Migration[7.0]
  def change
    create_table :gatherings do |t|
      t.string :name
      t.references :gathering_category, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :location

      t.timestamps
    end
    add_column :gatherings, :deleted_at, :datetime
    add_index :gatherings, [:starts_at, :ends_at]
  end
end
