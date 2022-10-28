class CreateReservations < ActiveRecord::Migration[7.0]
  def change
    create_table :reservations do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.date :from_date
      t.date :to_date

      t.timestamps
    end
  end
end
