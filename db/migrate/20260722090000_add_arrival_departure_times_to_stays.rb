class AddArrivalDepartureTimesToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :arrival_time, :string
    add_column :stays, :departure_time, :string
  end
end
