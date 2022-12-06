class AddOptionsToBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :bookings, :option_babysitting, :boolean
    add_column :bookings, :option_partyhall, :boolean
    add_column :bookings, :option_bread, :boolean
  end
end
