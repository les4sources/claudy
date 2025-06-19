class CreateWatchmanNotes < ActiveRecord::Migration[7.0]
  def change
    create_table :watchman_notes do |t|
      t.date :date
      t.text :note

      t.timestamps
    end
    add_index :watchman_notes, :date
  end
end
