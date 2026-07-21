class CreateCoworkingReservations < ActiveRecord::Migration[7.0]
  def change
    create_table :coworking_reservations do |t|
      t.references :coworking_pack, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.date :date, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :coworking_reservations, :date
    add_index :coworking_reservations, :deleted_at
  end
end
