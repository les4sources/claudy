class ChangeReservations < ActiveRecord::Migration[7.0]
  def change
    remove_column :reservations, :from_date
    remove_column :reservations, :to_date
    add_column :reservations, :date, :date
  end
end
