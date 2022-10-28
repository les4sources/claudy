class CreateLodgingRooms < ActiveRecord::Migration[7.0]
  def change
    create_table :lodging_rooms do |t|
      t.references :lodging, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true

      t.timestamps
    end
  end
end
