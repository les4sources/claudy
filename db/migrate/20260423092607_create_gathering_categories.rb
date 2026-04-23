class CreateGatheringCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :gathering_categories do |t|
      t.string :name, null: false
      t.string :color, null: false
      t.time :default_start_time
      t.integer :default_duration_minutes

      t.timestamps
    end
    add_column :gathering_categories, :deleted_at, :datetime
  end
end
