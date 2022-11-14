class CreateEventCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :event_categories do |t|
      t.string :name
      t.string :color

      t.timestamps
    end
  end
end
