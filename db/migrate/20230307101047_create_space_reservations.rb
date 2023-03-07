class CreateSpaceReservations < ActiveRecord::Migration[7.0]
  def change
    create_table :space_reservations do |t|
      t.references :space_booking, null: false, foreign_key: true
      t.references :event, null: true, foreign_key: true
      t.references :space, null: false, foreign_key: true
      t.date :date
      t.string :duration

      t.timestamps
    end
  end
end
